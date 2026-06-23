# frozen_string_literal: true

class Guestbook
  # Fly.io's proxy sets Fly-Client-IP to the peer that actually connected, so
  # the client can't forge it. That makes it the trusted peer: requests
  # fronted by Cloudflare or a custom proxy carry that proxy's address here,
  # and the matching forwarder reveals the real client behind it.
  module Fly
    module_function

    # A peer callable reading Fly-Client-IP, falling back to REMOTE_ADDR when
    # the header is absent (e.g. running off Fly).
    def peer
      ->(env) { env["HTTP_FLY_CLIENT_IP"] || env["REMOTE_ADDR"] }
    end
  end
end
