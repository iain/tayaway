# frozen_string_literal: true

module Notifications
  module Preferences
    # Turns off every configurable channel for the given kind. Forced
    # channels are skipped rather than rejected: this is a "shut up about
    # this" action from the bell, not a fine-grained PUT, and the caller
    # shouldn't have to know which channels are locked.
    module Silence
      class << self
        def call(user_id:, kind:)
          Success()
            .bind { lookup_kind(kind) }
            .bind { |kind_class| silence(user_id, kind_class) }
        end

        private

        def lookup_kind(kind)
          Success(Registry.fetch(kind))
        rescue KeyError
          Failure(ServiceError.validation("Unknown notification kind: #{kind.inspect}"))
        end

        def silence(user_id, kind_class)
          forced = forced_channels(kind_class)
          configurable = kind_class.supported_channels - forced
          configurable.each do |channel|
            UserNotificationPreference.upsert(
              user_id: user_id,
              kind: kind_class.key,
              channel: channel,
              enabled: false
            )
          end
          Success({ kind: kind_class.key.to_s, silenced: configurable.map(&:to_s) })
        end

        def forced_channels(kind_class)
          kind_class.respond_to?(:forced_channels) ? kind_class.forced_channels : []
        end
      end
    end
  end
end
