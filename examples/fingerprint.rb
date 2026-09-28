# frozen_string_literal: true

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

url = ARGV[0] || "https://www.browserscan.net/"
output = ARGV[1] || "browserscan.png"
png = client.screenshot(
  **routing,
  url: url,
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
File.binwrite(output, png)
puts "Saved fingerprint-check screenshot to #{output}"
