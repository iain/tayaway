# frozen_string_literal: true

class NotificationSerializer
  extend PoolObjectSerializer

  class << self
    def topics_for(notification)
      ["user:#{notification.user_id}"]
    end

    def serialize_batch(notifications, pool:)
      notifications.map(&:to_api_hash)
    end
  end
end
