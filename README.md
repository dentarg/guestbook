# Guestbook

[![CI](https://github.com/dentarg/guestbook/actions/workflows/ci.yml/badge.svg)](https://github.com/dentarg/guestbook/actions/workflows/ci.yml)

Rack middleware that logs one [logfmt](https://brandur.org/logfmt) line per
request — Host header included, so it stays useful when one app serves many
virtual hosts. It resolves the real client IP from forwarding headers, but
only trusts a header when the request demonstrably arrived through the proxy
that sets it — so client-supplied headers from an untrusted peer can't forge
the logged IP; they're reported as `spoofed=…` and ignored.

```
at=info method=GET host=example.com path=/oom query="year=2026" status=200 bytes=2 duration=0.0004 ip=203.0.113.7
```

It replaces a web server's built-in request logging (e.g. Puma's
`log_requests`, whose Apache common-log format omits the `Host` header —
useless when one app serves many virtual hosts).

## Installation

```ruby
# Gemfile
gem "guestbook"
```

## Usage

Add it to your `config.ru`. With no configuration it logs the connecting
socket as the client IP — correct when nothing fronts your app:

```ruby
require "guestbook"

use Guestbook
run YourApp
```

Behind a proxy, tell it two things: how to find the **trusted peer** and which
**forwarders** to honour (see [the model](#the-model) below).

```ruby
use Guestbook,
    peer: Guestbook::Fly.peer,
    forwarders: [Guestbook::Cloudflare.forwarder]
```

### The model

Every request reaches your app from some immediate **peer**. If your app is
exposed directly, that peer *is* the client. Behind a proxy it's the proxy,
and the real client lives in a forwarding header — which only means something
when the request actually came through that proxy.

- **`peer:`** — a callable `->(env) { ip }` returning the address you can
  trust as the immediate sender. Defaults to `REMOTE_ADDR` (the connecting
  socket). Platform presets override it where the socket isn't the real edge.

- **`forwarders:`** — an ordered list of `Guestbook::Forwarder`. Each names a
  header carrying the real client IP and the proxy ranges allowed to set it.
  The first forwarder whose ranges contain the peer wins; a header arriving
  from any other peer is flagged `spoofed` and ignored.

The logged IP is therefore: the first trusted forwarder's header, else the
peer.

### Providers

The presets just supply the right `peer`/`forwarder` for each platform —
nothing about them is special-cased in the middleware, so you can mix and
match freely.

**Fly.io** sets `Fly-Client-IP` to the peer that actually connected, so it
can't be forged:

```ruby
use Guestbook, peer: Guestbook::Fly.peer
```

**Heroku**'s router appends the connecting peer to `X-Forwarded-For`; the
rightmost entry is the trustworthy one:

```ruby
use Guestbook, peer: Guestbook::Heroku.peer
```

**Cloudflare** sets `CF-Connecting-IP` to the visitor; trust it only when the
peer is one of Cloudflare's published edge ranges. Compose it with whichever
peer fronts Cloudflare — e.g. Cloudflare in front of Fly:

```ruby
use Guestbook,
    peer: Guestbook::Fly.peer,
    forwarders: [Guestbook::Cloudflare.forwarder]
```

**An in-house proxy** (nginx, HAProxy, …) setting `X-Real-IP` — build a
`Forwarder` from your proxy's addresses:

```ruby
nginx = Guestbook::Forwarder.new(header: "X-Real-IP", ranges: %w[10.0.0.0/8])
use Guestbook, forwarders: [Guestbook::Cloudflare.forwarder, nginx]
```

`Cloudflare.forwarder` accepts `header:` and `ranges:` to override the bundled
list (e.g. `header: "True-Client-IP"` on Enterprise, or your own pinned
ranges).

### Options

| Option        | Default       | Description                                                              |
| ------------- | ------------- | ------------------------------------------------------------------------ |
| `io`          | `$stdout`     | Where lines are written (2nd positional arg).                            |
| `peer:`       | `REMOTE_ADDR` | Callable resolving the trusted peer.                                     |
| `forwarders:` | `[]`          | Ordered `Forwarder` list.                                                |
| `timestamps:` | `true`        | Prefix an ISO8601 UTC timestamp. Disable where the platform timestamps.  |

Disable `timestamps` in production when your platform's log shipper already
prepends one (Fly, Heroku); keep it on locally so server output is timestamped:

```ruby
use Guestbook, timestamps: ENV["RACK_ENV"] != "production"
```

### Logged fields

`at` (always `info`), `method`, `host`, `path`, `query` (omitted when empty),
`status`, `bytes` (response `Content-Length`, omitted when absent), `duration`
(seconds), `ip`, and `spoofed` (comma-separated header names, omitted when
none). Values containing whitespace, `"` or `=` are quoted.

Under Puma, logging is deferred via `rack.after_reply` so `duration` covers the
full request including writing the response. Servers without it (e.g. Falcon)
log inline.

## Examples

Runnable Rack and Sinatra apps are in [`examples/`](examples). Boot either
under any server:

```sh
PROVIDER=fly bundle exec puma examples/rack/config.ru
PROVIDER=fly bundle exec falcon serve --bind http://localhost:9292 examples/sinatra/config.ru
```

## Development

```sh
bundle install
bundle exec rake # runs the unit/example tests and rubocop
```

Integration tests boot a real server and assert what it logs. They're skipped
unless `GUESTBOOK_SERVER` is set, and each server runs under its own gemfile:

```sh
BUNDLE_GEMFILE=gemfiles/puma7.gemfile  GUESTBOOK_SERVER=puma   bundle exec rake test
BUNDLE_GEMFILE=gemfiles/puma8.gemfile  GUESTBOOK_SERVER=puma   bundle exec rake test
BUNDLE_GEMFILE=gemfiles/falcon.gemfile GUESTBOOK_SERVER=falcon bundle exec rake test
```

CI runs the unit suite across Ruby 3.3, 3.4 and 4.0, and the integration suite
against Puma 7, Puma 8 and Falcon.

## License

Released under the [MIT License](LICENSE).
