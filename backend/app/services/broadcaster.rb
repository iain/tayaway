# frozen_string_literal: true

require "json"

# Service module for broadcasting changes via PostgreSQL NOTIFY.
# Sends minimal payloads (type + id, plus topics for deletes) to stay
# under pg_notify's 8KB limit. The Listener fetches the full object,
# asks the registry for its topic set, and dispatches.
#
# Updates carry no topic info — the Listener loads the object and asks
# `entry.topics_for(obj)`. Deletes do carry topics because the object is
# gone by the time the Listener fires and can no longer be queried;
# topics ride the wire as their string form (Topic#to_json serializes
# as `"workspace:<id>"` / `"user:<id>"`).
#
# @example
#   Broadcaster.object_changed("event", event_id)
#   Broadcaster.object_changed("member", membership_id)
#   Broadcaster.object_deleted("notification", id, topics: [Topic.user(user_id)])
#   Broadcaster.object_deleted("event", id, topics: [Topic.workspace(workspace_id)])
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

    def object_deleted(object_type, object_id, topics:)
      topics = Array(topics)
      raise ArgumentError, "Broadcaster: object_deleted needs at least one topic" if topics.empty?
      raise ArgumentError, "Broadcaster: object_deleted topics: must be Topic instances" unless topics.all?(Topic)

      notify(
        objectType: object_type,
        objectId: object_id.to_s,
        action: "delete",
        topics: topics
      )
    end

    private

    def notify(**payload)
      DB.notify(CHANNEL, payload: payload.to_json)
    rescue StandardError => e
      APP_LOGGER.error { "[Broadcaster] Error sending notification: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}" }
    end
  end
end
