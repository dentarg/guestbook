# frozen_string_literal: true

require "ipaddr"

class Guestbook
  # An upstream proxy trusted to report the real client IP.
  #
  # When the connecting peer falls within +ranges+, the client IP is read
  # from +header+. The same header arriving from any other peer is treated as
  # a forgery: reported as spoofed and ignored.
  #
  #   Guestbook::Forwarder.new(header: "X-Real-IP", ranges: %w[10.0.0.0/8])
  class Forwarder
    # The Rack env key (e.g. "HTTP_X_REAL_IP") this forwarder reads from.
    attr_reader :env_key

    # The header in its spoofed-report form (e.g. "x-real-ip").
    attr_reader :label

    # header: the client-IP header this proxy sets, e.g. "CF-Connecting-IP".
    # ranges: IPs/CIDRs (String or IPAddr) the proxy connects from.
    def initialize(header:, ranges:)
      @env_key = "HTTP_#{header.upcase.tr('-', '_')}"
      @label = header.downcase
      @ranges = Array(ranges).map { |range| range.is_a?(IPAddr) ? range : IPAddr.new(range.to_s.strip) }.freeze
      freeze
    end

    # Is +peer+ one of this forwarder's trusted proxy addresses?
    def trusts?(peer)
      return false unless peer

      addr = IPAddr.new(peer)
      @ranges.any? { |range| range.include?(addr) }
    rescue IPAddr::Error
      false
    end
  end
end
