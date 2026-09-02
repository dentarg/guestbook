# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Expose proxy-resolved peer, client IP, and spoofed headers in the Rack
  environment for downstream middleware.
- Accept a `fields:` callable for application-specific log fields.
- Log the Heroku `X-Request-ID` header as `request_id` when present.
- Initial release: the `Guestbook` Rack middleware logging one logfmt line per
  request (Host header included), with proxy-aware client IP resolution and
  presets for Cloudflare, Fly.io and Heroku.
