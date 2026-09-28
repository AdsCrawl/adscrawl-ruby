# Releasing

The release workflow uses RubyGems Trusted Publishing, so the repository stores no long-lived RubyGems API key.

For the first release, create a pending trusted publisher in the RubyGems profile with:

- Gem name: `adscrawl`
- Repository owner: `AdsCrawl`
- Repository name: `adscrawl-ruby`
- Workflow filename: `release.yml`
- Environment: `release`

Then run `bundle exec rake test`, update `CHANGELOG.md`, and push a semantic version tag matching `AdsCrawl::VERSION`, such as `v0.1.0`. The workflow tests, builds, and publishes the Gem with a short-lived OIDC credential.

Published Gem versions cannot be reused. If a release needs a correction, increment the version and publish a new tag.
