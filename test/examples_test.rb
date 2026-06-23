# frozen_string_literal: true

require_relative "test_helper"
require "rack/builder"

# Exercises the shipped example apps through Rack::MockRequest, asserting the
# logfmt line each provider configuration produces. The middleware binds
# $stdout at `use` time, so we swap in a StringIO around the build and read it
# back after the request.
class ExamplesTest < Minitest::Test
  EXAMPLES = File.expand_path("../examples", __dir__)

  def request(config, env = {}, env_vars: {})
    app, log = build(config, env_vars)
    Rack::MockRequest.new(app).get("/", { "REMOTE_ADDR" => "203.0.113.7" }.merge(env))
    log.string
  end

  def build(config, env_vars)
    log = StringIO.new
    original_stdout = $stdout
    previous = env_vars.to_h { |key, _| [key, ENV[key]] }
    env_vars.each { |key, value| ENV[key] = value }
    $stdout = log
    [Rack::Builder.parse_file(File.join(EXAMPLES, config)), log]
  ensure
    $stdout = original_stdout
    previous&.each { |key, value| value.nil? ? ENV.delete(key) : (ENV[key] = value) }
  end

  def test_rack_example_honours_cloudflare_behind_fly
    line = request("rack/config.ru",
                   { "HTTP_FLY_CLIENT_IP" => "173.245.48.7", "HTTP_CF_CONNECTING_IP" => "192.0.2.9" },
                   env_vars: { "PROVIDER" => "fly", "RACK_ENV" => "production" })

    assert_match(/\Aat=info method=GET /, line) # production: no timestamp prefix
    assert_match(/ ip=192\.0\.2\.9\b/, line)
  end

  def test_rack_example_flags_forged_cloudflare_header
    line = request("rack/config.ru",
                   { "HTTP_FLY_CLIENT_IP" => "203.0.113.66", "HTTP_CF_CONNECTING_IP" => "192.0.2.9" },
                   env_vars: { "PROVIDER" => "fly", "RACK_ENV" => "production" })

    assert_match(/ ip=203\.0\.113\.66 spoofed=cf-connecting-ip/, line)
  end

  def test_rack_example_heroku_uses_rightmost_forwarded_for
    line = request("rack/config.ru",
                   { "HTTP_X_FORWARDED_FOR" => "1.1.1.1, 198.51.100.23" },
                   env_vars: { "PROVIDER" => "heroku", "RACK_ENV" => "production" })

    assert_match(/ ip=198\.51\.100\.23\b/, line)
  end

  def test_rack_example_honours_trusted_proxy_x_real_ip
    line = request("rack/config.ru",
                   { "HTTP_X_REAL_IP" => "198.51.100.4" },
                   env_vars: { "PROVIDER" => "none", "RACK_ENV" => "production",
                               "TRUSTED_PROXIES" => "203.0.113.0/24", })

    assert_match(/ ip=198\.51\.100\.4\b/, line)
  end

  def test_sinatra_example_logs_logfmt_line
    line = request("sinatra/config.ru",
                   { "HTTP_FLY_CLIENT_IP" => "173.245.48.7", "HTTP_CF_CONNECTING_IP" => "192.0.2.9" },
                   env_vars: { "PROVIDER" => "fly", "RACK_ENV" => "production" })

    assert_match(%r{\Aat=info method=GET host=\S+ path=/ status=200 .* ip=192\.0\.2\.9\b}, line)
  end
end
