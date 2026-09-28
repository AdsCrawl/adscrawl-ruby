# frozen_string_literal: true

module AdsCrawl
  module Service
    class CDP
      def initialize(client)
        @client = client
      end

      def create(options = nil, timeout_ms: nil, **keywords)
        payload = @client.options_hash(options, keywords)
        @client.validate_routing(payload)
        @client.request_json(
          "POST",
          "/cdp/sessions",
          payload,
          timeout_ms: timeout_ms,
          validate: ->(value) { @client.session?(value) }
        )
      end

      def list(timeout_ms: nil)
        @client.request_json(
          "GET",
          "/cdp/sessions",
          timeout_ms: timeout_ms,
          validate: lambda { |value|
            @client.ok?(value) && value["data"].is_a?(Array) && value["data"].all? { |session| @client.session?(session) }
          }
        )
      end

      def close(session_id, timeout_ms: nil)
        id = @client.encode_id(session_id)
        @client.request_json(
          "DELETE",
          "/cdp/sessions/#{id}",
          timeout_ms: timeout_ms,
          validate: ->(value) { @client.ok?(value) }
        )
      end

      # Discovers the WebSocket endpoint without forwarding the API key.
      def get_version(session, timeout_ms: nil)
        payload = @client.normalize_hash(session)
        session_id = payload["sessionId"]
        cdp_base_url = payload["cdpBaseUrl"]
        unless session_id.is_a?(String) && cdp_base_url.is_a?(String)
          raise ArgumentError, "The session must contain sessionId and a valid cdpBaseUrl."
        end

        id = @client.encode_id(session_id)
        parsed = URI.parse(cdp_base_url)
        base = @client.base_uri
        token = URI.decode_www_form(parsed.query.to_s).to_h["token"]
        expected_path = "#{base.path.to_s.sub(%r{/+\z}, "")}/cdp/sessions/#{id}"
        unless parsed.scheme == base.scheme && parsed.host == base.host && parsed.port == base.port &&
            parsed.path.sub(%r{/+\z}, "") == expected_path && !parsed.userinfo && !parsed.fragment &&
            token.is_a?(String) && !token.empty?
          raise ArgumentError, "cdpBaseUrl must belong to this API origin and session and include a data token."
        end

        path = "/cdp/sessions/#{id}/json/version?#{URI.encode_www_form(token: token)}"
        @client.request_json(
          "GET",
          path,
          timeout_ms: timeout_ms,
          authenticate: false,
          extra_secrets: [token],
          validate: ->(value) { @client.string?(value, "Browser") && @client.string?(value, "webSocketDebuggerUrl") }
        )
      rescue URI::InvalidURIError, ArgumentError => error
        raise error if error.message.start_with?("cdpBaseUrl")

        raise ArgumentError, "The session must contain sessionId and a valid cdpBaseUrl."
      end

      def live_token(session_id, timeout_ms: nil)
        @client.encode_id(session_id)
        @client.request_json(
          "POST",
          "/cdp/live-token",
          {"sessionId" => session_id},
          timeout_ms: timeout_ms,
          validate: lambda { |value|
            @client.ok?(value) && @client.string?(value, "controlUrl") && value["expiresAt"].is_a?(Numeric)
          }
        )
      end
    end
  end
end
