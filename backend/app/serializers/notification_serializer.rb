# frozen_string_literal: true

class NotificationSerializer
  class << self
    def serialize_batch(notifications, pool:)
      notifications.map(&:to_api_hash)
    end
  end
end
