# frozen_string_literal: true

require "ipaddr"
require "time"
require "rack"

require_relative "guestbook/version"

# Rack middleware that logs one logfmt line per request.
#
# The line includes the Host header, so it stays useful when one app serves
# many virtual hosts — unlike a web server's built-in common-log output.
#
# It resolves the real client IP from forwarding headers, but only trusts a
# header when the request demonstrably arrived through the proxy that sets it.
# A forwarding header arriving from any other peer is reported as +spoofed+
# and ignored, so it can't forge the logged IP.
#
#   use Guestbook,
#       peer: Guestbook::Fly.peer,
#       forwarders: [Guestbook::Cloudflare.forwarder]
#
# See Guestbook::Fly, Guestbook::Heroku and Guestbook::Cloudflare for the
# bundled presets, and Guestbook::Forwarder to add your own.
class Guestbook
  RACK_AFTER_REPLY = "rack.after_reply"
  RACK_ERRORS = "rack.errors"
  PEER = "guestbook.peer"
  CLIENT_IP = "guestbook.client_ip"
  SPOOFED = "guestbook.spoofed"

  # The peer used when no +peer:+ is configured: the address that opened the
  # connection, as the server saw it. Correct when nothing fronts the app.
  DEFAULT_PEER = ->(env) { env["REMOTE_ADDR"] }

  # peer: callable (env -> IP string or nil) returning the trusted peer, the
  #   address that actually connected to your edge. Defaults to REMOTE_ADDR;
  #   behind Fly use Guestbook::Fly.peer, behind Heroku Heroku.peer.
  #
  # forwarders: ordered Guestbook::Forwarder list. Each names a header
  #   carrying the real client IP and the proxy ranges allowed to set it. The
  #   first forwarder whose ranges contain the peer wins.
  #
  # fields: callable (env -> Hash) supplying application-specific fields to
  #   append to the log line. Core Guestbook fields cannot be overridden.
  #
  # timestamps: prefix each line with an ISO8601 UTC timestamp. Disable when
  #   the platform's log shipper already timestamps (e.g. Fly, Heroku).
  def initialize(app, io = $stdout, peer: DEFAULT_PEER, forwarders: [], fields: nil, timestamps: true)
    @app = app
    @io = io
    @peer = peer
    @forwarders = forwarders
    @fields = fields
    @timestamps = timestamps
  end

  def call(env)
    began_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # Resolve before calling the application so downstream middleware can use
    # the same trusted values Guestbook will log.
    resolve(env)
    status, headers, body = @app.call(env)
    log = -> { write_line(env, status, headers, began_at) }

    # Puma populates rack.after_reply; deferring until the response has been
    # written makes duration cover the full request. Servers without it
    # (e.g. Falcon) log inline.
    if (after_reply = env[RACK_AFTER_REPLY])
      after_reply << log
    else
      log.call
    end

    [status, headers, body]
  end

  private

  def write_line(env, status, headers, began_at)
    duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - began_at
    req = Rack::Request.new(env)
    pairs = {
      "at" => "info",
      "method" => req.request_method,
      "host" => req.host,
      "path" => req.path,
      "query" => req.query_string.empty? ? nil : req.query_string,
      "request_id" => env["HTTP_X_REQUEST_ID"],
      "status" => status,
      "bytes" => headers["content-length"],
      "duration" => format("%.4f", duration),
      "ip" => env[CLIENT_IP],
      "spoofed" => env[SPOOFED].empty? ? nil : env[SPOOFED].join(","),
    }
    @fields&.call(env)&.each { |key, value| pairs[key.to_s] = value unless pairs.key?(key.to_s) }
    line = pairs.filter_map { |key, value| "#{key}=#{quote(value)}" unless value.nil? }.join(" ")
    line = "#{Time.now.utc.iso8601(3)} #{line}" if @timestamps
    @io.write("#{line}\n")
  rescue StandardError => e
    env[RACK_ERRORS]&.puts("at=error logger=guestbook error=#{e.class} message=#{e.message.inspect}")
  end

  # Resolve the client IP. Start from the trusted peer; for each forwarder
  # whose ranges contain the peer, honor its header. A forwarder header
  # present from any other peer is flagged spoofed and ignored.
  def resolve(env)
    peer = @peer.call(env)
    ip = nil
    spoofed = []

    @forwarders.each do |forwarder|
      next unless (value = env[forwarder.env_key])

      if forwarder.trusts?(peer)
        ip ||= value
      else
        spoofed << forwarder.label
      end
    end

    env[PEER] = peer
    env[CLIENT_IP] = ip || peer
    env[SPOOFED] = spoofed
  end

  def quote(value)
    str = value.to_s
    str.match?(/[\s"=]/) || str.empty? ? str.inspect : str
  end
end

require_relative "guestbook/forwarder"
require_relative "guestbook/cloudflare"
require_relative "guestbook/fly"
require_relative "guestbook/heroku"
