# frozen_string_literal: true

require "json"
require "adscrawl"

client = AdsCrawl::Client.new
result = client.spa.extract(
  url: "https://www.adscrawl.net",
  fields: {
    title: {source: "dom", selector: "h1", value: "text", required: true}
  }
)
puts JSON.pretty_generate(
  title: result.dig("data", "title"),
  missingFields: result["missingFields"]
)
