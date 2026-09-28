# frozen_string_literal: true

module AdsCrawl
  class Error < StandardError; end

  class APIError < Error
    attr_reader :status, :api_code, :resource_id, :trace_id, :request_id, :body

    def initialize(message, status:, api_code: nil, resource_id: nil, trace_id: nil, request_id: nil, body: nil)
      @status = status
      @api_code = api_code
      @resource_id = resource_id
      @trace_id = trace_id
      @request_id = request_id
      @body = body
      super(message)
    end
  end

  class TimeoutError < Error
    attr_reader :timeout_ms

    def initialize(timeout_ms)
      @timeout_ms = timeout_ms
      super("AdsCrawl request timed out after #{timeout_ms}ms. Remote work may still be running; inspect sessions before retrying.")
    end
  end

  class ConnectionError < Error
    def initialize
      super("Unable to complete the AdsCrawl request. Check your network and service availability.")
    end
  end

  class ResponseError < Error; end
end
