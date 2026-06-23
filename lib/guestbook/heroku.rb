# frozen_string_literal: true

class Guestbook
  # Heroku's router appends the connecting peer to X-Forwarded-For. Only that
  # last hop is under Heroku's control, so it's the trusted peer; any entries
  # to its left are client-supplied and ignored. When Cloudflare or another
  # proxy fronts Heroku, the peer is that proxy and the matching forwarder
  # reveals the real client.
  module Heroku
    module_function

    # A peer callable reading the rightmost X-Forwarded-For entry, falling
    # back to REMOTE_ADDR when the header is absent.
    def peer
      lambda do |env|
        forwarded = env["HTTP_X_FORWARDED_FOR"]
        return env["REMOTE_ADDR"] unless forwarded

        forwarded.split(",").last&.strip || env["REMOTE_ADDR"]
      end
    end
  end
end
