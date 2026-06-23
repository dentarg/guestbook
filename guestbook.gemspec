# frozen_string_literal: true

require_relative "lib/guestbook/version"

Gem::Specification.new do |spec|
  spec.name = "guestbook"
  spec.version = Guestbook::VERSION
  spec.authors = ["Patrik Ragnarsson"]
  spec.email = ["patrik@starkast.net"]

  spec.summary = "Rack middleware that logs one logfmt line per request, with proxy-aware client IP resolution."
  spec.description = <<~DESC
    Guestbook is a small Rack middleware that writes one logfmt line per
    request, Host header included, so it stays useful when one app serves many
    virtual hosts. It resolves the real client IP from forwarding headers, but
    only trusts a header when the request demonstrably arrived through the
    proxy that sets it, so forged headers can't spoof the logged IP. Ships
    presets for Cloudflare, Fly.io and Heroku without hard-coding any of them.
  DESC
  spec.homepage = "https://github.com/dentarg/guestbook"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # Rack 3 normalises response headers to lower case, which the `bytes`
  # field relies on.
  spec.add_dependency "rack", ">= 3.0", "< 4"
end
