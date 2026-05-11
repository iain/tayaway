# frozen_string_literal: true

module Notifications
  module PushSubscriptions
    # Removes a browser's push-subscription credential. Scoped by user so a
    # signed-in user can't drop someone else's endpoint by guessing it.
    # Missing endpoints succeed silently — unsubscribe is idempotent from
    # the caller's perspective.
    module Unregister
      class << self
        def call(user_id:, endpoint:)
          PushSubscription.delete_by_endpoint(user_id: user_id, endpoint: endpoint.to_s)
          Success({ ok: true })
        end
      end
    end
  end
end
