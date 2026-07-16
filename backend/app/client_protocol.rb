# frozen_string_literal: true
# typed: true

# Client↔server protocol compatibility gate.
#
# The frontend bakes its PROTOCOL_VERSION (frontend/src/api/protocolVersion.ts)
# into every API request (X-Client-Version header) and WebSocket connect
# (`v` query param). Requests below MIN_SUPPORTED_VERSION are rejected —
# 426 Upgrade Required over HTTP, an `update_required` message over the
# WebSocket — which makes the client force-apply its pending service worker
# update instead of failing in confusing ways against an incompatible server.
#
# Bump discipline (see doc/protocol-versioning.md): the frontend bumps
# PROTOCOL_VERSION when it ships alongside a breaking change; this minimum
# is raised only when the old behavior is removed, after the fleet has had
# time to update. The gap between the two is the compatibility window.
#
# Named ClientProtocol rather than Protocol because the protocol-websocket
# gem owns ::Protocol.
module ClientProtocol
  # Raise log:
  # - 0: initial value — clients that predate versioning send no header and
  #   count as version 0, so they remain supported until this first moves.
  MIN_SUPPORTED_VERSION = 0

  class << self
    # A client-reported protocol version (raw header/param value — possibly
    # nil, garbage, or a repeated query param) as an integer; anything
    # unparseable counts as 0, the pre-versioning client.
    def parse(raw_version)
      Integer(raw_version.to_s, 10, exception: false) || 0
    end

    # Whether a client-reported protocol version meets the minimum.
    def supported?(raw_version)
      parse(raw_version) >= MIN_SUPPORTED_VERSION
    end
  end
end
