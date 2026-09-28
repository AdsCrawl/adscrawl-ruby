# frozen_string_literal: true

require "adscrawl"

client = AdsCrawl::Client.new
session = client.cdp.create(
  idleTimeoutMs: 600_000,
  maxSessionMs: 3_600_000,
  browserSettings: {viewport: {width: 1440, height: 900}}
)
begin
  version = client.cdp.get_version(session)
  puts version["Browser"] || "Unknown browser"
  puts "Connect a CDP-compatible Ruby library to session['cdpBaseUrl']."
ensure
  client.cdp.close(session["sessionId"])
end
