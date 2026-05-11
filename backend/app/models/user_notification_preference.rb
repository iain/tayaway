# frozen_string_literal: true

# Sparse override row for a user's notification preferences. The dispatcher
# starts from the kind's default channel set and applies these rows on top —
# absence means "use default", so new users and new kinds need no backfill.
class UserNotificationPreference < Data.define(:id, :user_id, :kind, :channel, :enabled, :created_at, :updated_at)
  class << self
    # Returns a `{ channel_symbol => bool }` hash of enabled-state overrides
    # for one user/kind. Channels not present in the hash fall back to the
    # kind's defaults.
    def overrides_for(user_id:, kind:)
      DB[:user_notification_preferences]
        .where(user_id: user_id, kind: kind.to_s)
        .select_map([:channel, :enabled])
        .to_h
        .transform_keys(&:to_sym)
    end

    def upsert(user_id:, kind:, channel:, enabled:)
      now = Time.now
      DB[:user_notification_preferences]
        .insert_conflict(
          target: %i[user_id kind channel],
          update: { enabled: enabled, updated_at: now }
        )
        .insert(
          user_id: user_id,
          kind: kind.to_s,
          channel: channel.to_s,
          enabled: enabled,
          created_at: now,
          updated_at: now
        )
    end
  end
end
