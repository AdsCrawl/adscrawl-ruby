# frozen_string_literal: true

require "adscrawl"

client = AdsCrawl::Client.new
url = ARGV[0] || "https://www.adscrawl.net"
output = ARGV[1] || "page.png"
png = client.screenshot(url: url, fullPage: true)
File.binwrite(output, png)
puts "Saved screenshot to #{output}"
