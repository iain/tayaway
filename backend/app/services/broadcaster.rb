# typed: true
# frozen_string_literal: true

require "json"

# Service module for broadcasting changes via PostgreSQL NOTIFY.
# Sends minimal payloads (channel + action) to stay under pg_notify's 8KB limit.
# The Listener fetches full data before broadcasting to WebSocket clients.
#
# @example
#   Broadcaster.object_changed("event", event_id)
#   Broadcaster.object_deleted("event", event_id)
#   Broadcaster.object_changed("vote", vote_id)
module Broadcaster
  CHANNEL = "tayaway_objects"

  class << self
    extend T::Sig

    sig { params(object_type: String, object_id: T.any(String, UUID)).void }
    def object_changed(object_type, object_id)
      notify(object_type, object_id, action: "update")
    end

    sig { params(object_type: String, object_id: T.any(String, UUID)).void }
    def object_deleted(object_type, object_id)
      notify(object_type, object_id, action: "delete")
    end

    private

    sig { params(object_type: String, object_id: T.any(String, UUID), action: String).void }
    def notify(object_type, object_id, action:)
      channel = "#{object_type}:#{object_id}"
      payload = { channel: channel, objectType: object_type, objectId: object_id.to_s, action: action }.to_json
      DB.run(Sequel.lit("SELECT pg_notify(?, ?)", CHANNEL, payload))
    rescue StandardError => e
      warn "[Broadcaster] Error sending notification: #{e.message}"
    end
  end
end
