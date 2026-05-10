# frozen_string_literal: true

require "json"

# Service module for broadcasting changes via PostgreSQL NOTIFY.
# Sends minimal payloads (audience + object info) to stay under pg_notify's 8KB limit.
# The Listener fetches full data before broadcasting to WebSocket clients.
#
# Audience selects who hears the change:
#   workspace_id: → fan out to every connection subscribed to that workspace
#                   (the standard collaborative path)
#   user_id:      → fan out to every connection authenticated as that user
#                   (per-user objects like notifications, read receipts, etc.)
#
# Exactly one of workspace_id: / user_id: must be passed.
#
# @example
#   Broadcaster.object_changed("event", event_id, workspace_id: workspace_id)
#   Broadcaster.object_changed("notification", notification_id, user_id: user_id)
#   Broadcaster.object_deleted("notification", notification_id, user_id: user_id)
module Broadcaster
  CHANNEL = "tayaway_objects"

  class << self
    def object_changed(object_type, object_id, workspace_id: nil, user_id: nil)
      notify(object_type, object_id, audience: build_audience(workspace_id, user_id), action: "update")
    end

    def object_deleted(object_type, object_id, workspace_id: nil, user_id: nil)
      notify(object_type, object_id, audience: build_audience(workspace_id, user_id), action: "delete")
    end

    private

    def build_audience(workspace_id, user_id)
      if workspace_id && user_id
        raise ArgumentError, "Broadcaster: pass exactly one of workspace_id: or user_id: as audience"
      elsif workspace_id
        { kind: "workspace", id: workspace_id.to_s }
      elsif user_id
        { kind: "user", id: user_id.to_s }
      else
        raise ArgumentError, "Broadcaster: missing audience — pass workspace_id: or user_id:"
      end
    end

    def notify(object_type, object_id, audience:, action:)
      payload = {
        audience: audience[:kind],
        audienceId: audience[:id],
        objectType: object_type,
        objectId: object_id.to_s,
        action: action
      }.to_json
      DB.run(Sequel.lit("SELECT pg_notify(?, ?)", CHANNEL, payload))
    rescue StandardError => e
      APP_LOGGER.error { "[Broadcaster] Error sending notification: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
    end
  end
end
