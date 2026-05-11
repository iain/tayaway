# frozen_string_literal: true

module Notifications
  module Inbox
    # Returns the recipient's recent notifications wrapped in a pool envelope.
    # The same envelope shape lets the frontend hand the response straight
    # to the shared object pool, where live WebSocket broadcasts also land.
    module List
      class << self
        def call(user_id:)
          notifications = Notification.for_user(user_id)
          pool = PoolSerializer.new
          pool.add(:notification, notifications)
          Success({ objects: pool.to_a })
        end
      end
    end
  end
end
