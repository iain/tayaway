# frozen_string_literal: true

require "json"

# Service module for broadcasting changes via PostgreSQL NOTIFY.
# Sends minimal payloads (type + id) to stay under pg_notify's 8KB limit.
# The Listener fetches the full object, asks ObjectRegistry to derive the
# audience set for the change, and fans out to every connection in each
# derived audience.
#
# Updates carry no audience info — the Listener loads the object and looks
# it up. Deletes do carry audience info because the object is gone by the
# time the Listener fires and can no longer be queried.
#
# @example
#   Broadcaster.object_changed("event", event_id)
#   Broadcaster.object_changed("member", membership_id)  # fans out to ws + user
#   Broadcaster.object_deleted("notification", notification_id, user_id: user_id)
#   Broadcaster.object_deleted("event", event_id, workspace_id: workspace_id)
module Broadcaster
  CHANNEL = "tayaway_objects"

  class << self
    def object_changed(object_type, object_id)
      notify(
        objectType: object_type,
        objectId: object_id.to_s,
        action: "update"
      )
    end

    def object_deleted(object_type, object_id, workspace_id: nil, user_id: nil)
      audience = build_audience(workspace_id, user_id)
      notify(
        objectType: object_type,
        objectId: object_id.to_s,
        action: "delete",
        audience: audience[:kind],
        audienceId: audience[:id]
      )
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

    def notify(**payload)
      DB.run(Sequel.lit("SELECT pg_notify(?, ?)", CHANNEL, payload.to_json))
    rescue StandardError => e
      APP_LOGGER.error { "[Broadcaster] Error sending notification: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
    end
  end
end
