# frozen_string_literal: true

require "adscrawl"

client = AdsCrawl::Client.new
url = ARGV[0] || "https://www.adscrawl.net"
puts client.markdown(url: url, waitUntil: "domcontentloaded")
