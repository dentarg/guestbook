# frozen_string_literal: true

# Plain Rack example. Boot it with any server:
#
#   bundle exec puma   examples/rack/config.ru
#   bundle exec falcon serve --bind http://localhost:9292 examples/rack/config.ru
#
# The trusted peer is chosen from PROVIDER (fly | heroku | none); set
# TRUSTED_PROXIES to a comma-separated list of CIDRs to also honour
# X-Real-IP from an in-house proxy. See the project README for the model.

require "guestbook"

$stdout.sync = true

peer =
  case ENV["PROVIDER"]
  when "fly"    then Guestbook::Fly.peer
  when "heroku" then Guestbook::Heroku.peer
  else Guestbook::DEFAULT_PEER
  end

# Honour Cloudflare's CF-Connecting-IP when the peer is a Cloudflare edge,
# plus an optional in-house proxy whose X-Real-IP we trust.
forwarders = [Guestbook::Cloudflare.forwarder]
if (proxies = ENV["TRUSTED_PROXIES"])
  forwarders << Guestbook::Forwarder.new(header: "X-Real-IP", ranges: proxies.split(","))
end

use Guestbook,
    peer: peer,
    forwarders: forwarders,
    timestamps: ENV["RACK_ENV"] != "production"

run ->(_env) { [200, { "content-type" => "text/plain" }, ["ok\n"]] }
