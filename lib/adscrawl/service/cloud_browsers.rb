# frozen_string_literal: true

module AdsCrawl
  module Service
    class CloudBrowsers
      def initialize(client)
        @client = client
      end

      def list(options = nil, timeout_ms: nil, **keywords)
        payload = @client.options_hash(options, keywords)
        query = payload.slice("page", "pageSize")
        path = query.empty? ? "/cloud-browsers" : "/cloud-browsers?#{URI.encode_www_form(query)}"
        @client.request_json(
          "GET",
          path,
          timeout_ms: timeout_ms,
          validate: lambda { |value|
            @client.ok?(value) && value["data"].is_a?(Array) &&
              value["data"].all? { |browser| @client.cloud_browser?(browser) } &&
              value["pagination"].is_a?(Hash) &&
              %w[limit runningLimit runningCount].all? { |key| value[key].is_a?(Integer) }
          }
        )
      end

      def create(options = nil, timeout_ms: nil, **keywords)
        payload = @client.options_hash(options, keywords)
        @client.validate_routing(payload)
        @client.request_json(
          "POST",
          "/cloud-browsers",
          payload,
          timeout_ms: timeout_ms,
          validate: ->(value) { @client.ok?(value) && @client.string?(value, "id") }
        )
      end

      def get(browser_id, timeout_ms: nil)
        id = @client.encode_id(browser_id)
        @client.request_json(
          "GET",
          "/cloud-browsers/#{id}",
          timeout_ms: timeout_ms,
          validate: ->(value) { @client.cloud_browser?(value) }
        )
      end

      def start(browser_id, options = nil, timeout_ms: nil, **keywords)
        id = @client.encode_id(browser_id)
        payload = require_proxy(@client.options_hash(options, keywords), "starts")
        @client.request_json(
          "POST",
          "/cloud-browsers/#{id}/start",
          payload,
          timeout_ms: timeout_ms,
          validate: ->(value) { @client.ok?(value) && @client.runtime?(value["runtime"]) }
        )
      end

      def stop(browser_id, timeout_ms: nil)
        id = @client.encode_id(browser_id)
        @client.request_json(
          "POST",
          "/cloud-browsers/#{id}/stop",
          timeout_ms: timeout_ms,
          validate: ->(value) { @client.ok?(value) && @client.runtime?(value["runtime"]) }
        )
      end

      def launch(options = nil, timeout_ms: nil, **keywords)
        payload = require_proxy(@client.options_hash(options, keywords), "launches")
        deadline = timeout_ms || @client.launch_timeout_ms
        @client.request_json(
          "POST",
          "/cloud-browsers/launch",
          payload,
          timeout_ms: deadline,
          validate: lambda { |value|
            @client.ok?(value) && @client.string?(value, "id") && value["source"] == "launch" &&
              value["deleteOnStop"] == false && @client.runtime?(value["runtime"])
          }
        )
      end

      private

      def require_proxy(options, action)
        payload = @client.normalize_hash(options)
        unless payload["proxy"].is_a?(Hash)
          raise ArgumentError, "Cloud browser #{action} require an explicit top-level proxy."
        end

        payload
      end
    end
  end
end
