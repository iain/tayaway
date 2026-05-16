# frozen_string_literal: true

module Notifications
  module Inbox
    # Marks one notification read for the current user and broadcasts the
    # change so the user's other devices/tabs pick up the new read_at
    # without a refresh. Already-read rows update nothing and broadcast
    # nothing — the SQL's `read_at: nil` predicate makes the call
    # idempotent.
    module MarkRead
      class << self
        def call(id:, user_id:)
          affected = Notification.mark_read(id, user_id: user_id)
          Broadcast.fan_out(affected)
          Success({ ok: true })
        end
      end
    end
  end
end
