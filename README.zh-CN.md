<p align="center">
  <a href="https://www.adscrawl.net/?utm_source=github&utm_medium=sdk&utm_campaign=adscrawl-ruby">
    <img src="assets/adscrawl-logo.svg" alt="AdsCrawl" width="360" />
  </a>
</p>

<p align="center"><strong>真实浏览器、结构化提取、截图与自动化。</strong></p>

<h1 align="center">Ruby SDK</h1>

把 URL 转换为浏览器渲染后的 HTML、Markdown、结构化数据或 PNG 截图；也可以创建远程 CDP 会话和管理持久云浏览器。

[官网](https://www.adscrawl.net/?utm_source=github&utm_medium=sdk&utm_campaign=adscrawl-ruby) · [API 文档](https://www.adscrawl.net/docs/) · [获取 API Key](https://app.adscrawl.net/register/?utm_source=rubygems&utm_medium=sdk&utm_campaign=adscrawl-ruby) · [English](./README.md)

- 支持 Ruby 3.1+，除标准库外无运行时依赖。
- 支持 HTTP 超时、响应结构校验和错误信息凭据脱敏。
- Hash 和关键字参数与 HTTP API 使用相同的 camelCase 字段。
- 对计费请求和浏览器创建请求不会自动重试。

## 安装

```bash
gem install adscrawl
```

也可以添加到 Bundle：

```bash
bundle add adscrawl
```

## 第一个请求

[注册账号](https://app.adscrawl.net/register/?utm_source=rubygems&utm_medium=sdk&utm_campaign=adscrawl-ruby)，创建 API Key，并在服务端环境变量中设置 `ADSCRAWL_API_KEY`。

```ruby
require "adscrawl"

client = AdsCrawl::Client.new
markdown = client.markdown(
  url: "https://www.adscrawl.net",
  waitUntil: "domcontentloaded"
)
puts markdown
```

也可以使用 `AdsCrawl::Client.new(api_key: "...")`。API Key 应只保存在服务端。仓库包含完整可运行的 [Markdown](./examples/markdown.rb)、[截图](./examples/screenshot.rb)、[结构化提取](./examples/extract.rb)、[指纹检测](./examples/fingerprint.rb)、[CDP](./examples/cdp.rb) 和 [云浏览器](./examples/cloud_browser.rb) 示例。

## 渲染内容与截图

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

`html` 返回 HTML，`markdown` 返回 Markdown，`article` 返回 Hash，`screenshot` 返回 PNG 二进制数据。页面参数支持视口、语言、Cookie、自定义 `proxy`、托管 `countryCode`、浏览器指纹、服务端 `timeoutMs` 与导航 `waitUntil`。自定义代理和托管国家线路不能同时使用。

## 代理与指纹：BrowserScan 截图

AdsCrawl 使用真实浏览器，并支持配置线路和浏览器指纹。以下示例默认使用 `GLOBAL` 托管线路；设置代理环境变量后则使用自定义代理。示例访问 [BrowserScan](https://www.browserscan.net/) 并保存返回截图。同一套浏览器流程也可访问和渲染 [Pixelscan](https://pixelscan.net/) 与 [IPhey](https://iphey.com/)，可从返回页面查看网站当前的检测结果。

```ruby
require "adscrawl"

client = AdsCrawl::Client.new
server = ENV["ADSCRAWL_PROXY_SERVER"]
username = ENV["ADSCRAWL_PROXY_USERNAME"]
password = ENV["ADSCRAWL_PROXY_PASSWORD"]
raise "代理用户名和密码必须同时设置。" if username.nil? != password.nil?
raise "使用代理凭据时必须设置 ADSCRAWL_PROXY_SERVER。" if server.nil? && (username || password)

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

可运行 `ruby examples/fingerprint.rb`，也可以把检测网站 URL 和输出路径作为参数传入。示例不会把自定义代理和托管线路组合使用。

## 结构化提取

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

## 远程 CDP 浏览器

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
  # 使用兼容 CDP 的 Ruby 库连接 session["cdpBaseUrl"]。
ensure
  client.cdp.close(session["sessionId"])
end
```

`client.cdp.list` 返回活动会话。`get_version` 会校验会话 Token URL，并且不会把 API Key 转发到数据端点。CDP 连接 URL 含有密钥，请勿写入日志。

## 持久云浏览器

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

使用 API Key 启动或快速创建云浏览器时，每次都必须传顶层自定义代理。返回 `stopping` 表示仍在关闭，需要轮询 `get` 直到状态为 `stopped`。快速创建失败时，`APIError#resource_id` 可能包含需要清理的浏览器 ID。

## 配置与错误处理

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
  puts "重试前请先检查远程会话。"
end
```

API Key 默认读取 `ADSCRAWL_API_KEY`。基础 URL 依次读取 `ADSCRAWL_BASE_URL`、`ADSCRAWL_API_URL`，最后使用 `https://api.adscrawl.net`。错误类型包括 `APIError`、`TimeoutError`、`ConnectionError` 和 `ResponseError`。API 错误响应会进行凭据脱敏。HTTP 超时包含读取响应体的时间。SDK 不会自动重试请求。

## 开发与发布

```bash
bundle install
bundle exec rake test
gem build adscrawl.gemspec
```

测试只使用本机和模拟响应，不消耗 AdsCrawl 额度。发布使用 RubyGems Trusted Publishing，不保存长期注册表 Token，详见 [RELEASING.md](./RELEASING.md)。

## 许可证

MIT
