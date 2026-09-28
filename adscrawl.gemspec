# frozen_string_literal: true

require_relative "lib/adscrawl/version"

Gem::Specification.new do |spec|
  spec.name = "adscrawl"
  spec.version = AdsCrawl::VERSION
  spec.authors = ["AdsCrawl"]
  spec.email = ["support@adscrawl.net"]

  spec.summary = "Official Ruby SDK for the AdsCrawl browser and extraction API"
  spec.description = "Render pages in real browsers, extract structured data, capture screenshots, open CDP sessions, and manage cloud browsers."
  spec.homepage = "https://www.adscrawl.net"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "bug_tracker_uri" => "https://github.com/AdsCrawl/adscrawl-ruby/issues",
    "changelog_uri" => "https://github.com/AdsCrawl/adscrawl-ruby/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://www.adscrawl.net/docs/",
    "homepage_uri" => spec.homepage,
    "rubygems_mfa_required" => "true",
    "source_code_uri" => "https://github.com/AdsCrawl/adscrawl-ruby"
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "examples/**/*.rb",
    "assets/adscrawl-logo.svg",
    "CHANGELOG.md",
    "LICENSE",
    "README.md",
    "README.zh-CN.md",
    "RELEASING.md"
  ].sort
  spec.require_paths = ["lib"]
end
