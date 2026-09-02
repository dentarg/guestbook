# frozen_string_literal: true

require_relative "test_helper"

class GuestbookTest < Minitest::Test
  # Drive a single request through the middleware and return what it logged.
  # Defaults exercise the common Fly + Cloudflare setup; pass +peer:+ or
  # +forwarders:+ to vary it.
  def logged(url, env = {}, peer: Guestbook::Fly.peer, forwarders: :cloudflare,
             timestamps: false, status: 200, headers: { "content-length" => "2" })
    forwarders = [Guestbook::Cloudflare.forwarder] if forwarders == :cloudflare
    io = StringIO.new
    app = Guestbook.new(->(_env) { [status, headers, ["ok"]] }, io,
                        peer: peer, forwarders: forwarders, timestamps: timestamps)
    app.call(Rack::MockRequest.env_for(url, { "REMOTE_ADDR" => "203.0.113.7" }.merge(env)))
    io.string
  end

  def test_logs_logfmt_line_with_host
    line = logged("https://tor.golf/oom?year=2026")

    assert_equal "at=info method=GET host=tor.golf path=/oom query=\"year=2026\" " \
                 "status=200 bytes=2 duration=0.0000 ip=203.0.113.7\n",
                 line.sub(/duration=\d+\.\d{4}/, "duration=0.0000")
  end

  def test_prefixes_iso8601_timestamp_when_enabled
    line = logged("/", timestamps: true)

    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z at=info /, line)
  end

  def test_defers_logging_to_rack_after_reply_when_present
    io = StringIO.new
    app = Guestbook.new(->(_env) { [200, {}, ["ok"]] }, io, timestamps: false)
    after_reply = []

    app.call(Rack::MockRequest.env_for("/", "rack.after_reply" => after_reply))

    assert_equal "", io.string
    after_reply.each(&:call)
    assert_match(/\Aat=info method=GET /, io.string)
  end

  def test_exposes_resolution_to_the_application
    seen = nil
    app = Guestbook.new(lambda { |env|
      seen = env
      [200, {}, ["ok"]]
    }, StringIO.new, peer: Guestbook::Fly.peer,
                     forwarders: [Guestbook::Cloudflare.forwarder], timestamps: false)

    app.call(Rack::MockRequest.env_for("/",
                                       "HTTP_FLY_CLIENT_IP" => "173.245.48.7",
                                       "HTTP_CF_CONNECTING_IP" => "192.0.2.9"))

    assert_equal "173.245.48.7", seen[Guestbook::PEER]
    assert_equal "192.0.2.9", seen[Guestbook::CLIENT_IP]
    assert_equal [], seen[Guestbook::SPOOFED]
  end

  def test_logs_additional_fields_set_by_the_application
    io = StringIO.new
    fields = ->(env) { { "crawler" => env["example.crawler"], "ua" => env["HTTP_USER_AGENT"] } }
    app = Guestbook.new(lambda { |env|
      env["example.crawler"] = "ExampleBot"
      [451, {}, ["blocked"]]
    }, io, fields: fields, timestamps: false)

    app.call(Rack::MockRequest.env_for("/", "HTTP_USER_AGENT" => "Example Bot/1.0"))

    assert_match(%r{ crawler=ExampleBot ua="Example Bot/1\.0"\z}, io.string.chomp)
  end

  # The default peer (no provider preset) is the connecting address.
  def test_default_peer_logs_remote_addr
    line = logged("/", peer: Guestbook::DEFAULT_PEER, forwarders: [])

    assert_match(/ ip=203\.0\.113\.7\z/, line.chomp)
  end

  def test_prefers_fly_client_ip_over_remote_addr
    line = logged("/", { "HTTP_FLY_CLIENT_IP" => "2001:db8::1" })

    assert_match(/ ip=2001:db8::1\z/, line.chomp)
  end

  def test_logs_fly_request_id
    line = logged("/", { "HTTP_FLY_REQUEST_ID" => "01JZ3M20F5W2Q819XJJ3P42WQ3-ord" })

    assert_match(/ request_id=01JZ3M20F5W2Q819XJJ3P42WQ3-ord\b/, line)
  end

  def test_honors_cf_connecting_ip_when_peer_is_cloudflare
    line = logged("/", {
                    "HTTP_CF_CONNECTING_IP" => "192.0.2.9",
                    "HTTP_FLY_CLIENT_IP" => "2400:cb00:1032:1000::1",
                  })

    assert_match(/ ip=192\.0\.2\.9\z/, line.chomp)
  end

  # Heroku's router appends the connecting peer to X-Forwarded-For; the
  # rightmost entry is the trustworthy one.
  def test_heroku_peer_uses_rightmost_forwarded_for
    line = logged("/", { "HTTP_X_FORWARDED_FOR" => "1.1.1.1, 198.51.100.23" },
                  peer: Guestbook::Heroku.peer, forwarders: [])

    assert_match(/ ip=198\.51\.100\.23\z/, line.chomp)
  end

  def test_logs_heroku_request_id
    line = logged("/", {
                    "HTTP_X_FORWARDED_FOR" => "198.51.100.23",
                    "HTTP_X_REQUEST_ID" => "f9ed4675f1c53513c61a3b3b4e25b4c0",
                  }, peer: Guestbook::Heroku.peer, forwarders: [])

    assert_match(/ request_id=f9ed4675f1c53513c61a3b3b4e25b4c0\b/, line)
  end

  def test_honors_x_real_ip_when_peer_is_a_trusted_proxy
    forwarders = [Guestbook::Forwarder.new(header: "X-Real-IP",
                                           ranges: ["212.63.204.17", "2a01:298:f6:ffff::f"])]
    line = logged("/", {
                    "HTTP_X_REAL_IP" => "198.51.100.4",
                    "HTTP_FLY_CLIENT_IP" => "2a01:298:f6:ffff::f",
                  }, forwarders: forwarders)

    assert_match(/ ip=198\.51\.100\.4\z/, line.chomp)
  end

  # A client connecting straight to the edge can send these headers, but the
  # peer gives the forgery away: the header is flagged and ignored.
  def test_flags_forged_headers_from_untrusted_peer
    forwarders = [Guestbook::Cloudflare.forwarder,
                  Guestbook::Forwarder.new(header: "X-Real-IP", ranges: ["10.0.0.0/8"]),]
    line = logged("/", {
                    "HTTP_CF_CONNECTING_IP" => "192.0.2.9",
                    "HTTP_X_REAL_IP" => "198.51.100.4",
                    "HTTP_FLY_CLIENT_IP" => "203.0.113.66",
                  }, forwarders: forwarders)

    assert_match(/ ip=203\.0\.113\.66 spoofed=cf-connecting-ip,x-real-ip\z/, line.chomp)
  end

  # A malformed peer must not raise; it simply trusts nothing.
  def test_malformed_peer_is_not_trusted
    line = logged("/", {
                    "HTTP_CF_CONNECTING_IP" => "192.0.2.9",
                    "HTTP_FLY_CLIENT_IP" => "not-an-ip",
                  })

    assert_match(/ ip=not-an-ip spoofed=cf-connecting-ip\z/, line.chomp)
  end

  # A logging failure must be swallowed and reported to rack.errors, never
  # propagated to the application.
  def test_logs_error_to_rack_errors_without_raising
    errors = StringIO.new
    io = Object.new.tap { |obj| def obj.write(_) = raise("disk full") }
    app = Guestbook.new(->(_env) { [200, { "content-length" => "2" }, ["ok"]] }, io,
                        forwarders: [], timestamps: false)

    app.call(Rack::MockRequest.env_for("/", "rack.errors" => errors))

    assert_match(/at=error logger=guestbook error=RuntimeError/, errors.string)
  end
end
