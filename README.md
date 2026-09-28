<p align="center">
  <a href="https://www.adscrawl.net/?utm_source=github&utm_medium=sdk&utm_campaign=adscrawl-ruby">
    <img src="assets/adscrawl-logo.svg" alt="AdsCrawl" width="360" />
  </a>
</p>

<p align="center"><strong>Real browsers. Structured extraction. Screenshots and automation.</strong></p>

<h1 align="center">Ruby SDK</h1>

Turn a URL into rendered HTML, readable Markdown, structured data, or a PNG screenshot. Open remote CDP sessions and manage persistent cloud browsers with the same API as the TypeScript, Python, Go, and PHP SDKs.

[Website](https://www.adscrawl.net/?utm_source=github&utm_medium=sdk&utm_campaign=adscrawl-ruby) · [API documentation](https://www.adscrawl.net/docs/) · [Get an API key](https://app.adscrawl.net/register/?utm_source=rubygems&utm_medium=sdk&utm_campaign=adscrawl-ruby) · [中文](./README.zh-CN.md)

- Ruby 3.1+ with no runtime dependencies outside the standard library.
- Explicit HTTP deadlines, checked response shapes, and credential-redacted errors.
- Hash and keyword arguments use the HTTP API's camelCase field names.
- No automatic retries of metered requests or browser creation.

## Install

```bash
gem install adscrawl
```

Or add it to your bundle:

```bash
bundle add adscrawl
```

## Your first request

[Create an account](https://app.adscrawl.net/register/?utm_source=rubygems&utm_medium=sdk&utm_campaign=adscrawl-ruby), create an API key, and set `ADSCRAWL_API_KEY` in your server environment.

```ruby
require "adscrawl"

client = AdsCrawl::Client.new
markdown = client.markdown(
  url: "https://www.adscrawl.net",
  waitUntil: "domcontentloaded"
)
puts markdown
```

You can also use `AdsCrawl::Client.new(api_key: "...")`. Keep API keys in server-side code. See the complete runnable examples for [Markdown](./examples/markdown.rb), [screenshots](./examples/screenshot.rb), [structured extraction](./examples/extract.rb), [fingerprints](./examples/fingerprint.rb), [CDP](./examples/cdp.rb), and [cloud browsers](./examples/cloud_browser.rb).

## Rendered content and screenshots

```ruby
require "adscrawl"

client = AdsCrawl::Client.new
html = client.html(url: "https://www.adscrawl.net")
article = client.article(url: "https://www.adscrawl.net")
puts [article["title"], article["textContent"]]

png = client.screenshot(
  url: "https://www.adscrawl.net",
  viewport: {width: 1440, height: 900},
  fullPage: true,
  waitUntil: "load"
)
File.binwrite("page.png", png)
```

`html` returns HTML, `markdown` returns Markdown, `article` returns a Hash, and `screenshot` returns binary PNG data. Page options include viewport, locale, cookies, custom `proxy`, managed `countryCode`, fingerprint, server-side `timeoutMs`, and navigation `waitUntil`. A custom proxy and managed country cannot be combined.

## Proxy and fingerprint: BrowserScan screenshot

AdsCrawl uses real browsers with configurable routing and browser fingerprints. This complete example uses managed `GLOBAL` routing unless proxy environment variables are present, opens [BrowserScan](https://www.browserscan.net/), and saves the returned screenshot. The same browser workflow can access and render [Pixelscan](https://pixelscan.net/) and [IPhey](https://iphey.com/); inspect the returned page for its current result.

```ruby
require "adscrawl"

client = AdsCrawl::Client.new
server = ENV["ADSCRAWL_PROXY_SERVER"]
username = ENV["ADSCRAWL_PROXY_USERNAME"]
password = ENV["ADSCRAWL_PROXY_PASSWORD"]
raise "Set both proxy username and password, or neither." if username.nil? != password.nil?
raise "Set ADSCRAWL_PROXY_SERVER with proxy credentials." if server.nil? && (username || password)

routing = {countryCode: "GLOBAL"}
if server
  proxy = {server: server}
  proxy.merge!(username: username, password: password) if username && password
  routing = {proxy: proxy}
end

png = client.screenshot(
  **routing,
  url: "https://www.browserscan.net/",
  viewport: {width: 1440, height: 900},
  fullPage: true,
  waitUntil: "networkidle",
  timeoutMs: 60_000,
  userAgentMode: "random",
  userAgentOs: "windows",
  fingerprint: {
    webRtc: "forward", webGl: "random", webGpu: "random",
    webGlImage: "random", canvas: "random", audioContext: "random",
    clientRects: "random", speechVoices: "random", fonts: "random",
    hardware: "random", doNotTrack: "random"
  },
  timeout_ms: 75_000
)
File.binwrite("browserscan.png", png)
```

Run the included version with `ruby examples/fingerprint.rb`. Pass a detection URL and output path as optional arguments. The example never combines a custom proxy with managed routing.

## Structured extraction

```ruby
require "adscrawl"

client = AdsCrawl::Client.new
puts client.spa.templates["templates"]

result = client.spa.extract(
  url: "https://www.adscrawl.net",
  fields: {
    title: {source: "dom", selector: "h1", value: "text", required: true}
  }
)
puts result.dig("data", "title")

inspection = client.spa.inspect(url: "https://www.adscrawl.net")
puts inspection["candidates"]
```

## Remote CDP browsers

```ruby
require "adscrawl"

client = AdsCrawl::Client.new
session = client.cdp.create(
  idleTimeoutMs: 600_000,
  maxSessionMs: 3_600_000,
  browserSettings: {viewport: {width: 1440, height: 900}}
)
begin
  version = client.cdp.get_version(session)
  puts version["Browser"]
  # Connect a CDP-compatible Ruby library to session["cdpBaseUrl"].
ensure
  client.cdp.close(session["sessionId"])
end
```

`client.cdp.list` returns active sessions. `get_version` validates the session token URL and deliberately omits the API key. CDP connection URLs contain secrets; do not log them.

## Persistent cloud browsers

```ruby
require "adscrawl"

client = AdsCrawl::Client.new
launched = client.cloud_browsers.launch(
  proxy: {server: ENV.fetch("ADSCRAWL_PROXY_SERVER")},
  tabs: ["https://www.adscrawl.net"]
)
browser_id = launched["id"]
begin
  profile = client.cloud_browsers.get(browser_id)
  puts profile.dig("runtime", "status")
ensure
  client.cloud_browsers.stop(browser_id)
end
```

API-key starts and launches require an explicit top-level custom proxy. A `stopping` response means shutdown is pending; poll `get` until `stopped`. A failed launch may expose a cleanup profile ID as `APIError#resource_id`.

## Configuration and errors

```ruby
require "adscrawl"

client = AdsCrawl::Client.new(base_url: "https://api.adscrawl.net", timeout_ms: 90_000)
begin
  puts client.markdown(
    {url: "https://www.adscrawl.net", timeoutMs: 60_000},
    timeout_ms: 75_000
  )
rescue AdsCrawl::APIError => error
  puts [error.status, error.api_code, error.trace_id]
rescue AdsCrawl::TimeoutError
  puts "Inspect remote sessions before retrying."
end
```

The API key defaults to `ADSCRAWL_API_KEY`; the base URL defaults to `ADSCRAWL_BASE_URL`, then `ADSCRAWL_API_URL`, then `https://api.adscrawl.net`. Errors include `APIError`, `TimeoutError`, `ConnectionError`, and `ResponseError`. API response bodies are credential-redacted. The HTTP deadline includes response body reading. Requests are not automatically retried.

## Develop and release

```bash
bundle install
bundle exec rake test
gem build adscrawl.gemspec
```

Tests use local and fake responses and consume no AdsCrawl credits. Releases use RubyGems Trusted Publishing with no long-lived registry token; see [RELEASING.md](./RELEASING.md).

## License

MIT
