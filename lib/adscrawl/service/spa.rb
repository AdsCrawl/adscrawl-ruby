# frozen_string_literal: true

module AdsCrawl
  module Service
    class SPA
      def initialize(client)
        @client = client
      end

      def templates(timeout_ms: nil)
        @client.request_json(
          "GET",
          "/spa-extract/templates",
          timeout_ms: timeout_ms,
          validate: lambda { |value|
            value["templates"].is_a?(Array) && value["templates"].all? do |template|
              @client.string?(template, "id") && @client.string?(template, "name")
            end
          }
        )
      end

      def extract(options = nil, timeout_ms: nil, **keywords)
        payload = @client.options_hash(options, keywords)
        @client.validate_routing(payload)
        @client.request_json(
          "POST",
          "/spa-extract",
          payload.merge("mode" => "extract"),
          timeout_ms: timeout_ms,
          validate: lambda { |value|
            value["mode"] == "extract" && @client.page?(value["page"]) &&
              value["data"].is_a?(Hash) && value["missingFields"].is_a?(Array)
          }
        )
      end

      def inspect(options = nil, timeout_ms: nil, **keywords)
        payload = @client.options_hash(options, keywords)
        @client.validate_routing(payload)
        @client.request_json(
          "POST",
          "/spa-extract",
          payload.merge("mode" => "inspect"),
          timeout_ms: timeout_ms,
          validate: lambda { |value|
            value["mode"] == "inspect" && @client.page?(value["page"]) &&
              value["candidates"].is_a?(Hash) && value["suggestedPlan"].is_a?(Hash)
          }
        )
      end
    end
  end
end
