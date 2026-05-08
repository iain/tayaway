# frozen_string_literal: true

module Notifications
  # Single entry point for every outbound notification. Resolves which
  # channels to use (kind defaults overlaid with the user's preferences,
  # unless the kind is non-configurable) and hands each channel an
  # opaque `data` payload that the kind's per-channel renderer knows how
  # to consume.
  module Dispatch
    class << self
      # Channels that need a `user_id` to deliver to; if none is
      # supplied (e.g. workspace invite to a brand-new email), the
      # dispatcher quietly drops them rather than failing the call.
      USER_REQUIRED_CHANNELS = %i[in_app push].freeze

      # @param kind [Symbol] registry key
      # @param data [Hash] kind- and channel-specific payload, splatted
      #   into the per-channel delivery job's kwargs
      # @param user_id [String, nil] used for preference lookup; pass nil
      #   when the recipient has no user yet (e.g. an invite to an email
      #   that hasn't signed up), in which case the kind's defaults apply
      #   and user-bound channels are skipped
      # @param workspace_id [String, nil] required for the in-app channel
      #   (notifications carry a workspace for filtering and link targets)
      def call(kind:, data:, user_id: nil, workspace_id: nil)
        kind_class = Registry.fetch(kind)
        channels = effective_channels(kind_class, user_id)
        channels.each { |channel| dispatch(channel, kind_class, data, user_id, workspace_id) }
      end

      private

      def effective_channels(kind_class, user_id)
        channels =
          if user_id.nil?
            kind_class.default_channels
          else
            apply_overrides(kind_class, user_id)
          end
        user_id.nil? ? channels - USER_REQUIRED_CHANNELS : channels
      end

      def apply_overrides(kind_class, user_id)
        defaults = kind_class.default_channels
        overrides = UserNotificationPreference.overrides_for(user_id: user_id, kind: kind_class.key)
        defaults.select { |channel| overrides.fetch(channel, true) } +
          overrides.select { |channel, enabled| enabled && !defaults.include?(channel) }.keys
      end

      def dispatch(channel, kind_class, data, user_id, workspace_id)
        case channel
        when :email
          Channels::Email.deliver_later(kind_class: kind_class, data: data)
        when :in_app
          Channels::InApp.deliver(
            kind_class: kind_class,
            user_id: user_id,
            workspace_id: workspace_id,
            data: data
          )
        else
          raise ArgumentError, "Unknown notification channel: #{channel.inspect}"
        end
      end
    end
  end
end
