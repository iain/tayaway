# frozen_string_literal: true

module Notifications
  module Inbox
    # Internal helper: turn the array of `{ id: ... }` rows that MarkRead
    # and MarkAllRead get back from the DB into per-user notify calls.
    # Lives next to its callers because it's their shared shape, not a
    # general-purpose broadcaster concern.
    module Broadcast
      class << self
        def fan_out(rows, user_id)
          uid = user_id.to_s
          rows.each { |row| Broadcaster.object_changed("notification", row[:id], user_id: uid) }
        end
      end
    end
  end
end
