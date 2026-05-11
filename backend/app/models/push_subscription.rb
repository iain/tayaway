# frozen_string_literal: true

# Browser push-subscription credential. Created via
# `POST /api/notifications/push-subscriptions` after the browser has
# returned a PushManager subscription; consumed by
# `Notifications::Channels::Push` when fanning a notification out.
class PushSubscription < Data.define(:id, :user_id, :endpoint, :p256dh_key, :auth_key, :user_agent, :created_at, :updated_at)
  class << self
    def for_user(user_id)
      dataset.where(user_id: user_id).all
    end

    # Browsers only hand out one subscription per (origin, service worker),
    # so a re-subscribe for an existing endpoint should refresh the keys
    # rather than create a duplicate row. ON CONFLICT also moves the
    # subscription to the current user when a different account signs
    # in on the same browser.
    def upsert(user_id:, endpoint:, p256dh_key:, auth_key:, user_agent: nil)
      now = Time.now
      DB[:push_subscriptions]
        .insert_conflict(
          target: :endpoint,
          update: {
            user_id: user_id,
            p256dh_key: p256dh_key,
            auth_key: auth_key,
            user_agent: user_agent,
            updated_at: now
          }
        )
        .insert(
          user_id: user_id,
          endpoint: endpoint,
          p256dh_key: p256dh_key,
          auth_key: auth_key,
          user_agent: user_agent,
          created_at: now,
          updated_at: now
        )
    end

    def delete_by_endpoint(user_id:, endpoint:)
      DB[:push_subscriptions].where(user_id: user_id, endpoint: endpoint).delete
    end

    def delete_endpoint(endpoint)
      DB[:push_subscriptions].where(endpoint: endpoint).delete
    end

    private

    def dataset
      DB[:push_subscriptions].with_row_proc(method(:from_row))
    end

    def from_row(row)
      new(
        id: row[:id],
        user_id: row[:user_id],
        endpoint: row[:endpoint],
        p256dh_key: row[:p256dh_key],
        auth_key: row[:auth_key],
        user_agent: row[:user_agent],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
