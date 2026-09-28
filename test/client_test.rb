# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "socket"
require "adscrawl"

class AdsCrawlClientTest < Minitest::Test
  def response(status: 200, headers: {}, body: "")
    AdsCrawl::HttpResponse.new(status: status, headers: headers, body: body)
  end

  def test_content_article_and_screenshot_requests
    calls = []
    transport = lambda do |**request|
      payload = request[:body] && JSON.parse(request[:body])
      calls << request.merge(payload: payload)
      case [URI(request[:url]).path, payload && payload["contentMode"]]
      when ["/html", "markdown"]
        response(body: "# AdsCrawl")
      when ["/html", "json"]
        response(body: JSON.generate(title: "AdsCrawl", content: "<p>x</p>", textContent: "x", length: 1))
      when ["/screenshot", nil]
        response(body: "\x89PNG\r\n\x1a\nbody".b)
      else
        raise "Unexpected request: #{request[:url]}"
      end
    end
    client = AdsCrawl::Client.new(api_key: "test-key", base_url: "https://api.example.test", transport: transport)

    assert_equal "# AdsCrawl", client.markdown(url: "https://www.adscrawl.net")
    assert_equal "AdsCrawl", client.article(url: "https://www.adscrawl.net")["title"]
    assert client.screenshot(url: "https://www.adscrawl.net").start_with?("\x89PNG".b)
    assert_equal 3, calls.length
    assert_equal "test-key", calls.first[:headers]["X-API-Key"]
    assert_equal "https://www.adscrawl.net", calls.first[:payload]["url"]
    assert_equal 90_000, calls.first[:timeout_ms]
  end

  def test_routing_cloud_proxy_and_resource_id_validation
    client = AdsCrawl::Client.new(api_key: "test-key", transport: ->(**) { flunk "Unexpected request" })
    error = assert_raises(ArgumentError) do
      client.markdown(url: "https://www.adscrawl.net", proxy: {server: "http://proxy.test:8080"}, countryCode: "US")
    end
    assert_includes error.message, "cannot be combined"
    assert_raises(ArgumentError) { client.cloud_browsers.launch({}) }
    assert_raises(ArgumentError) { client.cdp.close("..") }
  end

  def test_cdp_discovery_validates_token_url_and_omits_api_key
    session = {
      "sessionId" => "session/1",
      "expiresAt" => "2026-09-28T12:00:00Z",
      "cdpBaseUrl" => "https://api.example.test/cdp/sessions/session%2F1?token=secret-token"
    }
    transport = lambda do |**request|
      uri = URI(request[:url])
      case [request[:method], uri.path]
      when ["POST", "/cdp/sessions"]
        response(body: JSON.generate(session))
      when ["GET", "/cdp/sessions/session%2F1/json/version"]
        refute request[:headers].key?("X-API-Key")
        assert_equal "secret-token", URI.decode_www_form(uri.query).to_h["token"]
        response(body: JSON.generate("Browser" => "Chrome/136", "webSocketDebuggerUrl" => "wss://example.test/devtools"))
      when ["DELETE", "/cdp/sessions/session%2F1"]
        response(body: JSON.generate(ok: true))
      else
        raise "Unexpected request: #{request[:url]}"
      end
    end
    client = AdsCrawl::Client.new(api_key: "test-key", base_url: "https://api.example.test", transport: transport)
    created = client.cdp.create

    assert_equal "Chrome/136", client.cdp.get_version(created)["Browser"]
    assert_equal true, client.cdp.close(created["sessionId"])["ok"]
    created["cdpBaseUrl"] = "https://other.test/cdp/sessions/session%2F1?token=secret-token"
    assert_raises(ArgumentError) { client.cdp.get_version(created) }
  end

  def test_api_errors_redact_request_and_response_secrets
    transport = lambda do |**|
      response(
        status: 400,
        headers: {"X-Trace-Id" => "trace-test-key"},
        body: JSON.generate(
          error: "bad test-key password-secret",
          code: "BAD_REQUEST",
          id: "browser-1",
          password: "password-secret",
          url: "https://x.test/?token=token-secret"
        )
      )
    end
    client = AdsCrawl::Client.new(api_key: "test-key", transport: transport)
    error = assert_raises(AdsCrawl::APIError) do
      client.cloud_browsers.launch(proxy: {server: "http://proxy.test:8080", username: "user-secret", password: "password-secret"})
    end

    assert_equal 400, error.status
    assert_equal "BAD_REQUEST", error.api_code
    assert_equal "browser-1", error.resource_id
    assert_equal "trace-[REDACTED]", error.trace_id
    serialized = JSON.generate(error.body)
    %w[test-key password-secret token-secret].each do |secret|
      refute_includes "#{error.message}#{serialized}#{error.trace_id}", secret
    end
  end

  def test_spa_and_cloud_endpoints
    launch_timeout = nil
    transport = lambda do |**request|
      path = URI(request[:url]).path
      case path
      when "/spa-extract/templates"
        response(body: JSON.generate(templates: [{id: "x", name: "X"}]))
      when "/spa-extract"
        response(body: JSON.generate(mode: "extract", page: {url: "https://www.adscrawl.net", title: "AdsCrawl"}, data: {title: "AdsCrawl"}, missingFields: []))
      when "/cloud-browsers/launch"
        launch_timeout = request[:timeout_ms]
        response(body: JSON.generate(ok: true, id: "browser-1", source: "launch", deleteOnStop: false, runtime: {status: "running"}))
      else
        raise "Unexpected request: #{request[:url]}"
      end
    end
    client = AdsCrawl::Client.new(api_key: "test-key", transport: transport)

    assert_equal "x", client.spa.templates["templates"].first["id"]
    result = client.spa.extract(url: "https://www.adscrawl.net", fields: {title: {source: "dom", selector: "h1", value: "text"}})
    assert_equal "AdsCrawl", result["data"]["title"]
    launched = client.cloud_browsers.launch(proxy: {server: "http://proxy.test:8080"}, tabs: ["https://www.adscrawl.net"])
    assert_equal "browser-1", launched["id"]
    assert_equal 195_000, launch_timeout
  end

  def test_unexpected_json_shape_fails_closed
    client = AdsCrawl::Client.new(
      api_key: "test-key",
      transport: ->(**) { response(body: JSON.generate(title: "missing article fields")) }
    )
    assert_raises(AdsCrawl::ResponseError) { client.article(url: "https://www.adscrawl.net") }
  end

  def test_default_transport_does_not_follow_redirects
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      socket = server.accept
      request = +""
      request << socket.readpartial(1_024) until request.include?("\r\n\r\n")
      socket.write("HTTP/1.1 302 Found\r\nLocation: /unexpected\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
      socket.close
    rescue EOFError, IOError
      nil
    end
    client = AdsCrawl::Client.new(api_key: "test-key", base_url: "http://127.0.0.1:#{server.addr[1]}")
    error = assert_raises(AdsCrawl::APIError) { client.markdown(url: "https://www.adscrawl.net") }
    assert_equal 302, error.status
  ensure
    server&.close
    thread&.join(1)
  end

  def test_default_transport_maps_deadlines_to_timeout_error
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      socket = server.accept
      request = +""
      request << socket.readpartial(1_024) until request.include?("\r\n\r\n")
      sleep 0.2
      socket.close
    rescue EOFError, IOError
      nil
    end
    client = AdsCrawl::Client.new(
      api_key: "test-key",
      base_url: "http://127.0.0.1:#{server.addr[1]}",
      timeout_ms: 50
    )
    error = assert_raises(AdsCrawl::TimeoutError) { client.markdown(url: "https://www.adscrawl.net") }
    assert_equal 50, error.timeout_ms
  ensure
    server&.close
    thread&.join(1)
  end
end
