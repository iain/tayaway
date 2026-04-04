# typed: strict
# frozen_string_literal: true

# Minimal shim for maxminddb gem (GeoIP lookups).
# The auto-generated RBI is typed: ignore because it uses C extensions.

class MaxMindDB
  sig { params(path: String).void }
  def initialize(path); end

  sig { params(ip: String).returns(T.untyped) }
  def lookup(ip); end
end
