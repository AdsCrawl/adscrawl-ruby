# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "socket"
require "timeout"
require "uri"

require_relative "errors"
require_relative "http_response"
require_relative "service/spa"
require_relative "service/cdp"
require_relative "service/cloud_browsers"

module AdsCrawl
  class Client
    DEFAULT_BASE_URL = "https://api.adscrawl.net"
    DEFAULT_TIMEOUT_MS = 90_000
    LAUNCH_TIMEOUT_MS = 195_000
    MAX_TIMEOUT_MS = 2_147_483_647
    MAX_BODY_BYTES = 64 * 1024 * 1024
    PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b
    RUNTIME_STATUSES = %w[starting running stopping stopped].freeze

    attr_reader :spa, :cdp, :cloud_browsers
    alias cloudBrowsers cloud_browsers

    # Construction never performs a network request.
    # A custom transport receives keyword arguments and returns HttpResponse.
    def initialize(api_key: nil, base_url: nil, timeout_ms: nil, transport: nil)
      selected_key = (api_key || ENV["ADSCRAWL_API_KEY"]).to_s.strip
      raise ArgumentError, "Set ADSCRAWL_API_KEY or pass api_key to Client." if selected_key.empty?
      raise ArgumentError, "api_key must not contain line breaks." if selected_key.match?(/[\r\n]/)

      selected_url = base_url || ENV["ADSCRAWL_BASE_URL"] || ENV["ADSCRAWL_API_URL"] || DEFAULT_BASE_URL
      @base_uri = validate_base_url(selected_url)
      @base_url = selected_url.sub(%r{/+\z}, "")
      @api_key = selected_key
      @timeout_ms = validate_timeout(timeout_ms || DEFAULT_TIMEOUT_MS)
      @custom_timeout = !timeout_ms.nil?
      @transport = transport

      @spa = Service::SPA.new(self)
      @cdp = Service::CDP.new(self)
      @cloud_browsers = Service::CloudBrowsers.new(self)
    end

    def html(options = nil, timeout_ms: nil, **keywords)
      payload = options_hash(options, keywords)
      validate_routing(payload)
      body = send_request("POST", "/html", payload.merge("contentMode" => "html"), timeout_ms: timeout_ms)
      raise ResponseError, "AdsCrawl returned empty page content." if body.strip.empty?

      body.dup.force_encoding(Encoding::UTF_8)
    end

    def markdown(options = nil, timeout_ms: nil, **keywords)
      payload = options_hash(options, keywords)
      validate_routing(payload)
      body = send_request("POST", "/html", payload.merge("contentMode" => "markdown"), timeout_ms: timeout_ms)
      raise ResponseError, "AdsCrawl returned empty page content." if body.strip.empty?

      body.dup.force_encoding(Encoding::UTF_8)
    end

    def article(options = nil, timeout_ms: nil, **keywords)
      payload = options_hash(options, keywords)
      validate_routing(payload)
      request_json(
        "POST",
        "/html",
        payload.merge("contentMode" => "json"),
        timeout_ms: timeout_ms,
        validate: lambda { |value|
          string?(value, "title") && string?(value, "content") &&
            string?(value, "textContent") && value["length"].is_a?(Numeric)
        }
      )
    end

    def screenshot(options = nil, timeout_ms: nil, **keywords)
      payload = options_hash(options, keywords)
      validate_routing(payload)
      body = send_request("POST", "/screenshot", payload, timeout_ms: timeout_ms)
      raise ResponseError, "AdsCrawl returned an invalid PNG screenshot." unless body.b.start_with?(PNG_SIGNATURE)

      body.b
    end

    # Internal API used by service objects.
    def send_request(method, path, body = nil, timeout_ms: nil, authenticate: true, extra_secrets: [])
      deadline = validate_timeout(timeout_ms || @timeout_ms)
      payload = body.nil? ? nil : normalize_hash(body)
      secrets = [@api_key, *collect_secrets(payload), *extra_secrets].compact
      encoded = payload.nil? ? nil : JSON.generate(payload)
      headers = {"Accept" => "*/*", "User-Agent" => "adscrawl-ruby/#{VERSION}"}
      headers["X-API-Key"] = @api_key if authenticate
      headers["Content-Type"] = "application/json" unless encoded.nil?

      response = if @transport
        @transport.call(method: method, url: "#{@base_url}#{path}", headers: headers, body: encoded, timeout_ms: deadline)
      else
        net_http_request(method, "#{@base_url}#{path}", headers, encoded, deadline)
      end
      raise ResponseError, "The custom transport must return an AdsCrawl::HttpResponse." unless response.is_a?(HttpResponse)
      raise ResponseError, "AdsCrawl response exceeds the 64 MiB safety limit." if response.body.bytesize > MAX_BODY_BYTES

      status = Integer(response.status)
      return response.body if status.between?(200, 299)

      raise_api_error(status, response.body, response.headers || {}, secrets)
    end

    # Internal API used by service objects.
    def request_json(method, path, body = nil, timeout_ms: nil, authenticate: true, validate: nil, extra_secrets: [])
      raw = send_request(
        method,
        path,
        body,
        timeout_ms: timeout_ms,
        authenticate: authenticate,
        extra_secrets: extra_secrets
      )
      value = JSON.parse(raw)
      raise ResponseError, "AdsCrawl returned invalid or unexpected JSON." unless value.is_a?(Hash)
      if validate && !validate.call(value)
        raise ResponseError, "AdsCrawl returned an unexpected JSON response shape."
      end

      value
    rescue JSON::ParserError
      raise ResponseError, "AdsCrawl returned invalid or unexpected JSON."
    end

    def launch_timeout_ms
      @custom_timeout ? nil : LAUNCH_TIMEOUT_MS
    end

    def base_uri
      @base_uri.dup
    end

    def normalize_hash(value)
      raise ArgumentError, "options must be a Hash." unless value.is_a?(Hash)

      normalize_value(value)
    end

    def options_hash(options, keywords)
      if options && !keywords.empty?
        raise ArgumentError, "Pass options as a Hash or keywords, not both."
      end

      normalize_hash(options || keywords)
    end

    def validate_routing(value)
      return unless value.is_a?(Hash)

      if value.key?("proxy") && !value["proxy"].nil? && value.key?("countryCode") && !value["countryCode"].to_s.empty?
        raise ArgumentError, "proxy and countryCode cannot be combined."
      end
      validate_routing(value["browserSettings"]) if value["browserSettings"].is_a?(Hash)
    end

    def encode_id(value)
      raise ArgumentError, "A non-empty resource id is required." unless value.is_a?(String) && !value.strip.empty? && !%w[. ..].include?(value)

      URI.encode_www_form_component(value).tr("+", "%20")
    end

    def ok?(value)
      value.is_a?(Hash) && value["ok"] == true
    end

    def session?(value)
      value.is_a?(Hash) && string?(value, "sessionId") && string?(value, "expiresAt") && string?(value, "cdpBaseUrl")
    end

    def runtime?(value)
      value.is_a?(Hash) && RUNTIME_STATUSES.include?(value["status"])
    end

    def cloud_browser?(value)
      value.is_a?(Hash) && string?(value, "id") && runtime?(value["runtime"]) && value["browserSettings"].is_a?(Hash)
    end

    def page?(value)
      value.is_a?(Hash) && string?(value, "url") && string?(value, "title")
    end

    def string?(value, key)
      value.is_a?(Hash) && value[key].is_a?(String)
    end

    private

    def validate_base_url(value)
      uri = URI.parse(value.to_s)
      unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && !uri.query && !uri.fragment
        raise ArgumentError, "base_url must be an HTTP(S) URL without credentials, query, or fragment."
      end

      uri
    rescue URI::InvalidURIError
      raise ArgumentError, "base_url must be an HTTP(S) URL without credentials, query, or fragment."
    end

    def validate_timeout(value)
      unless value.is_a?(Integer) && value.positive? && value <= MAX_TIMEOUT_MS
        raise ArgumentError, "timeout_ms must be a positive Integer no greater than #{MAX_TIMEOUT_MS}."
      end

      value
    end

    def normalize_value(value)
      case value
      when Hash
        value.each_with_object({}) { |(key, item), result| result[key.to_s] = normalize_value(item) }
      when Array
        value.map { |item| normalize_value(item) }
      else
        value
      end
    end

    def net_http_request(method, url, headers, body, timeout_ms)
      uri = URI.parse(url)
      request_class = {
        "GET" => Net::HTTP::Get,
        "POST" => Net::HTTP::Post,
        "DELETE" => Net::HTTP::Delete
      }.fetch(method)
      request = request_class.new(uri.request_uri, headers)
      request.body = body unless body.nil?
      timeout_seconds = timeout_ms / 1000.0
      response_headers = {}
      response_body = String.new(encoding: Encoding::BINARY)
      status = nil

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = [timeout_seconds, 10.0].min
      http.read_timeout = timeout_seconds
      http.write_timeout = timeout_seconds if http.respond_to?(:write_timeout=)
      http.request(request) do |response|
        status = response.code.to_i
        response.each_header { |name, value| response_headers[name.downcase] = value }
        response.read_body do |chunk|
          if response_body.bytesize + chunk.bytesize > MAX_BODY_BYTES
            raise ResponseError, "AdsCrawl response exceeds the 64 MiB safety limit."
          end
          response_body << chunk.b
        end
      end

      HttpResponse.new(status: status, headers: response_headers, body: response_body)
    rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Timeout::Error
      raise TimeoutError, timeout_ms
    rescue ResponseError
      raise
    rescue SocketError, OpenSSL::SSL::SSLError, EOFError, IOError, SystemCallError, URI::InvalidURIError
      raise ConnectionError
    end

    def raise_api_error(status, raw, headers, secrets)
      parsed = JSON.parse(raw)
    rescue JSON::ParserError
      parsed = raw.to_s
    ensure
      safe_body = redact_value(parsed, secrets)
      message = "AdsCrawl API returned HTTP #{status}"
      api_code = resource_id = trace_id = nil
      if safe_body.is_a?(Hash)
        message = safe_body["error"] if safe_body["error"].is_a?(String)
        api_code = safe_body["code"] if safe_body["code"].is_a?(String)
        resource_id = safe_body["id"] if safe_body["id"].is_a?(String)
        trace_id = safe_body["traceId"] if safe_body["traceId"].is_a?(String)
      end
      normalized_headers = headers.each_with_object({}) { |(key, value), result| result[key.to_s.downcase] = value.to_s }
      trace_id = redact_string(normalized_headers["x-trace-id"], secrets) if normalized_headers["x-trace-id"]
      request_id = normalized_headers["x-request-id"] && redact_string(normalized_headers["x-request-id"], secrets)
      raise APIError.new(
        message.to_s.slice(0, 2048),
        status: status,
        api_code: api_code,
        resource_id: resource_id,
        trace_id: trace_id,
        request_id: request_id,
        body: safe_body
      )
    end

    def collect_secrets(value, result = [])
      case value
      when Hash
        value.each do |key, item|
          if key == "cookies" && item.is_a?(Array)
            item.each { |cookie| result << cookie["value"] if cookie.is_a?(Hash) && cookie["value"].is_a?(String) && !cookie["value"].empty? }
          end
          if %w[password username token controltoken].include?(key.downcase) && item.is_a?(String) && !item.empty?
            result << item
          end
          collect_secrets(item, result)
        end
      when Array
        value.each { |item| collect_secrets(item, result) }
      end
      result
    end

    def redact_string(value, secrets)
      output = value.to_s.dup
      secrets.each { |secret| output.gsub!(secret, "[REDACTED]") unless secret.to_s.empty? }
      output.gsub!(/([?&](?:token|controlToken|apiKey|api_key)=)[^&#\s"<>]+/i, '\\1[REDACTED]')
      output.gsub!(/(\b(?:https?|socks5):\/\/)[^\s\/@]+:[^\s\/@]+@/i, '\\1[REDACTED]@')
      output
    end

    def redact_value(value, secrets)
      case value
      when String
        redact_string(value, secrets)
      when Array
        value.map { |item| redact_value(item, secrets) }
      when Hash
        value.each_with_object({}) do |(key, item), result|
          normalized = key.to_s.downcase.delete("-_")
          result[key] = if %w[apikey xapikey authorization password username cookie cookies token controltoken websocketdebuggerurl cdpbaseurl controlurl connecturl].include?(normalized)
            "[REDACTED]"
          else
            redact_value(item, secrets)
          end
        end
      else
        value
      end
    end
  end
end
