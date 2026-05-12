# frozen_string_literal: true

module Notifications
  module PushSubscriptions
    # Stores or refreshes a browser push-subscription credential for the
    # signed-in user. The `endpoint` URL the browser hands back is the
    # natural unique key (one subscription per service worker), so the
    # underlying upsert refreshes the row when the same browser re-
    # subscribes — same endpoint, possibly new keys.
    module Register
      class << self
        def call(user_id:, endpoint:, p256dh_key:, auth_key:, user_agent: nil)
          Success()
            .bind { validate(endpoint) }
            .bind { store(user_id, endpoint, p256dh_key, auth_key, user_agent) }
        end

        private

        def validate(endpoint)
          if endpoint.to_s.empty?
            Failure(ServiceError.validation("endpoint is required"))
          else
            Success()
          end
        end

        def store(user_id, endpoint, p256dh_key, auth_key, user_agent)
          PushSubscription.upsert(
            user_id: user_id,
            endpoint: endpoint.to_s,
            p256dh_key: p256dh_key.to_s,
            auth_key: auth_key.to_s,
            user_agent: user_agent
          )
          Success({ ok: true, vapidPublicKey: APP_CONFIG.vapid_public_key.to_s })
        end
      end
    end
  end
end
