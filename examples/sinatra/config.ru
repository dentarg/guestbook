# frozen_string_literal: true

# Sinatra example. Boot it with any server:
#
#   bundle exec puma   examples/sinatra/config.ru
#   bundle exec falcon serve --bind http://localhost:9292 examples/sinatra/config.ru
#
# PROVIDER (fly | heroku | none) selects the trusted peer, exactly as in the
# Rack example — the middleware is wired the same way regardless of framework.

require "sinatra/base"
require "guestbook"

$stdout.sync = true

class ExampleApp < Sinatra::Base
  # Sinatra's own request logging duplicates ours; turn it off.
  disable :logging

  get "/" do
    content_type "text/plain"
    "ok\n"
  end
end

peer =
  case ENV["PROVIDER"]
  when "fly"    then Guestbook::Fly.peer
  when "heroku" then Guestbook::Heroku.peer
  else Guestbook::DEFAULT_PEER
  end

use Guestbook,
    peer: peer,
    forwarders: [Guestbook::Cloudflare.forwarder],
    timestamps: ENV["RACK_ENV"] != "production"

run ExampleApp
