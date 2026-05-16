# frozen_string_literal: true

module Notifications
  module Inbox
    # Internal helper: turn the array of `{ id: ... }` rows that MarkRead
    # and MarkAllRead get back from the DB into per-row notify calls.
    # Lives next to its callers because it's their shared shape, not a
    # general-purpose broadcaster concern. The user-audience fanout
    # happens in the Listener via NotificationSerializer.topics_for.
    module Broadcast
      class << self
        def fan_out(rows)
          rows.each { |row| Broadcaster.object_changed("notification", row[:id]) }
        end
      end
    end
  end
end
