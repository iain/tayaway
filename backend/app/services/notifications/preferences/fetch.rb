# frozen_string_literal: true

module Notifications
  module Preferences
    # Returns the current user's notification preferences as a kind ×
    # channel matrix with effective enabled state. Defaults come from the
    # kind's `default_channels`; stored override rows flip individual
    # cells. The frontend renders one toggle per cell.
    module Fetch
      class << self
        def call(user_id:)
          Success()
            .bind { Success(load_overrides(user_id)) }
            .bind { |overrides| Success({ kinds: build_matrix(overrides) }) }
        end

        private

        def load_overrides(user_id)
          DB[:user_notification_preferences]
            .where(user_id: user_id)
            .each_with_object({}) do |row, h|
              (h[row[:kind]] ||= {})[row[:channel]] = row[:enabled]
            end
        end

        def build_matrix(overrides)
          Registry.all.map do |kind_class|
            key = kind_class.key.to_s
            {
              key: key,
              channels: kind_class.supported_channels.map do |channel|
                channel_key = channel.to_s
                default_on = kind_class.default_channels.include?(channel)
                enabled = overrides.dig(key, channel_key)
                {
                  channel: channel_key,
                  enabled: enabled.nil? ? default_on : enabled
                }
              end
            }
          end
        end
      end
    end
  end
end
