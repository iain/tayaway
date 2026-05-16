# frozen_string_literal: true

module Notifications
  module Inbox
    # Marks every unread notification for the user read and broadcasts each
    # row that was actually flipped, so other devices/tabs sync. Rows that
    # were already read don't trigger a broadcast — the DB primitive only
    # returns ids whose read_at moved.
    module MarkAllRead
      class << self
        def call(user_id:)
          affected = Notification.mark_all_read(user_id)
          Broadcast.fan_out(affected)
          Success({ ok: true })
        end
      end
    end
  end
end
