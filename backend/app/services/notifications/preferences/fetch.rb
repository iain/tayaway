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
            forced = forced_channels(kind_class)
            {
              key: key,
              channels: kind_class.supported_channels.map do |channel|
                channel_key = channel.to_s
                is_forced = forced.include?(channel)
                default_on = kind_class.default_channels.include?(channel)
                enabled = overrides.dig(key, channel_key)
                {
                  channel: channel_key,
                  # Forced channels always read as on regardless of any
                  # stored override — the dispatcher ignores the override
                  # too, so showing it as off in the UI would lie to the
                  # user about what actually happens.
                  enabled: is_forced || (enabled.nil? ? default_on : enabled),
                  forced: is_forced
                }
              end
            }
          end
        end

        def forced_channels(kind_class)
          kind_class.respond_to?(:forced_channels) ? kind_class.forced_channels : []
        end
      end
    end
  end
end
