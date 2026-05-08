# frozen_string_literal: true

module Notifications
  # Single entry point for every outbound notification. Resolves which
  # channels to use (kind defaults overlaid with the user's preferences,
  # unless the kind is non-configurable) and hands each channel an
  # opaque `data` payload that the kind's per-channel renderer knows how
  # to consume.
  module Dispatch
    class << self
      # @param kind [Symbol] registry key
      # @param data [Hash] kind- and channel-specific payload, splatted
      #   into the per-channel delivery job's kwargs
      # @param user_id [String, nil] used for preference lookup; pass nil
      #   when the recipient has no user yet (e.g. an invite to an email
      #   that hasn't signed up), in which case the kind's defaults apply
      def call(kind:, data:, user_id: nil)
        kind_class = Registry.fetch(kind)
        channels = effective_channels(kind_class, user_id)
        channels.each { |channel| dispatch(channel, kind_class, data) }
      end

      private

      def effective_channels(kind_class, user_id)
        defaults = kind_class.default_channels
        return defaults if user_id.nil?

        overrides = UserNotificationPreference.overrides_for(user_id: user_id, kind: kind_class.key)
        defaults.select { |channel| overrides.fetch(channel, true) } +
          overrides.select { |channel, enabled| enabled && !defaults.include?(channel) }.keys
      end

      def dispatch(channel, kind_class, data)
        case channel
        when :email
          Channels::Email.deliver_later(kind_class: kind_class, data: data)
        else
          raise ArgumentError, "Unknown notification channel: #{channel.inspect}"
        end
      end
    end
  end
end
