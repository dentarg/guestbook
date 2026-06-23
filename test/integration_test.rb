# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "net/http"
require "socket"

# Boots a real web server (Puma or Falcon, selected by GUESTBOOK_SERVER)
# running the Rack example, then drives HTTP requests with crafted forwarding
# headers and asserts the logfmt line the middleware writes to the server's
# stdout.
#
# Run it per server, each under its matching gemfile:
#
#   BUNDLE_GEMFILE=gemfiles/puma8.gemfile  GUESTBOOK_SERVER=puma   bundle exec rake test
#   BUNDLE_GEMFILE=gemfiles/falcon.gemfile GUESTBOOK_SERVER=falcon bundle exec rake test
#
# Without GUESTBOOK_SERVER the test skips itself, so the default `rake test`
# run (which has no server gem) stays green.
class IntegrationTest < Minitest::Test
  SERVER = ENV["GUESTBOOK_SERVER"]
  CONFIG = File.expand_path("../examples/rack/config.ru", __dir__)
  BOOT_TIMEOUT = 25
  LINE_TIMEOUT = 5

  def test_resolves_client_ip_under_a_real_server
    skip "set GUESTBOOK_SERVER=puma|falcon (under the matching gemfile) to run" unless SERVER

    with_server do |port, output|
      # No forwarding headers: the peer is the connecting socket itself.
      assert_logged(output, port, "/plain", {}, %r{ path=/plain .* ip=127\.0\.0\.1\b})

      # Fly-Client-IP is the trusted peer and stands in as the client.
      assert_logged(output, port, "/fly",
                    { "Fly-Client-IP" => "2001:db8::1" },
                    %r{ path=/fly .* ip=2001:db8::1\b})

      # Peer is a Cloudflare edge, so CF-Connecting-IP is honoured.
      assert_logged(output, port, "/cf",
                    { "Fly-Client-IP" => "173.245.48.7", "CF-Connecting-IP" => "192.0.2.9" },
                    %r{ path=/cf .* ip=192\.0\.2\.9\b})

      # Peer is not Cloudflare: the CF header is a forgery, flagged and ignored.
      assert_logged(output, port, "/spoof",
                    { "Fly-Client-IP" => "203.0.113.66", "CF-Connecting-IP" => "192.0.2.9" },
                    %r{ path=/spoof .* ip=203\.0\.113\.66 spoofed=cf-connecting-ip\b})
    end
  end

  private

  def assert_logged(output, port, path, headers, pattern)
    response = http_get(port, path, headers)
    assert_equal("200", response.code, "unexpected status for #{path}")

    line = wait_for_line(output, "path=#{path} ")
    refute_nil(line, "no log line for #{path} within #{LINE_TIMEOUT}s; captured:\n#{output.text}")
    assert_match(pattern, line)
  end

  def with_server
    port = free_port
    env = { "PROVIDER" => "fly", "RACK_ENV" => "production" }
    stdin, out, wait_thr = Open3.popen2e(env, *server_command(port), pgroup: true)
    stdin.close
    output = CapturedOutput.new(out)

    wait_until_listening(port, wait_thr, output)
    yield port, output
  ensure
    stop(wait_thr)
    output&.close
  end

  def server_command(port)
    case SERVER
    when "puma"
      ["bundle", "exec", "puma", "-b", "tcp://127.0.0.1:#{port}", CONFIG]
    when "falcon"
      ["bundle", "exec", "falcon", "serve", "-b", "http://127.0.0.1:#{port}", "-n", "1", "-c", CONFIG]
    else
      raise "unknown GUESTBOOK_SERVER=#{SERVER.inspect} (expected puma or falcon)"
    end
  end

  def wait_until_listening(port, wait_thr, output)
    deadline = monotonic + BOOT_TIMEOUT
    loop do
      TCPSocket.new("127.0.0.1", port).close
      return
    rescue SystemCallError
      raise "#{SERVER} exited before listening:\n#{output.text}" unless wait_thr.alive?
      raise "#{SERVER} did not listen within #{BOOT_TIMEOUT}s:\n#{output.text}" if monotonic > deadline

      sleep 0.1
    end
  end

  def http_get(port, path, headers)
    http = Net::HTTP.new("127.0.0.1", port)
    http.open_timeout = http.read_timeout = LINE_TIMEOUT
    request = Net::HTTP::Get.new(path)
    headers.each { |key, value| request[key] = value }
    http.request(request)
  end

  # Our log line starts with "at=info" and carries the request path; require
  # both so we never match the server's own diagnostics.
  def wait_for_line(output, needle)
    deadline = monotonic + LINE_TIMEOUT
    loop do
      line = output.lines.find { |candidate| candidate.start_with?("at=info ") && candidate.include?(needle) }
      return line if line
      return nil if monotonic > deadline

      sleep 0.05
    end
  end

  def stop(wait_thr)
    return unless wait_thr&.alive?

    Process.kill("TERM", -wait_thr.pid)
    return unless wait_thr.join(3).nil?

    Process.kill("KILL", -wait_thr.pid)
  rescue Errno::ESRCH
    # Already gone.
  end

  def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Drains a server's combined stdout/stderr on a background thread so log
  # lines emitted after the HTTP response (Puma defers via rack.after_reply)
  # are still captured.
  class CapturedOutput
    def initialize(io)
      @lines = []
      @mutex = Mutex.new
      @thread = Thread.new do
        io.each_line { |line| @mutex.synchronize { @lines << line } }
      rescue IOError
        # Pipe closed on teardown.
      end
      @io = io
    end

    def lines
      @mutex.synchronize { @lines.dup }
    end

    def text
      lines.join
    end

    def close
      @io.close
    rescue IOError
      # Already closed.
    ensure
      @thread&.join(2)
    end
  end
end
