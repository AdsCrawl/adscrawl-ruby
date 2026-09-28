# frozen_string_literal: true

require "adscrawl"

proxy_server = ENV.fetch("ADSCRAWL_PROXY_SERVER")
client = AdsCrawl::Client.new
launched = client.cloud_browsers.launch(
  proxy: {server: proxy_server},
  tabs: ["https://www.adscrawl.net"]
)
browser_id = launched["id"]
begin
  profile = client.cloud_browsers.get(browser_id)
  puts "#{profile['id']} #{profile.dig('runtime', 'status')}"
ensure
  client.cloud_browsers.stop(browser_id)
end
