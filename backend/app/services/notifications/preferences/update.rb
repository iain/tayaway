# frozen_string_literal: true

module Notifications
  module Preferences
    # Upserts a single (kind, channel) override row for the current user.
    # Validates against the registry so a typo'd kind or channel rejects
    # cleanly rather than landing in the database.
    module Update
      class << self
        def call(user_id:, kind:, channel:, enabled:)
          Success()
            .bind { lookup_kind(kind) }
            .bind { |kind_class| validate_channel(kind_class, channel) }
            .bind { |kind_class| persist(user_id, kind_class.key, channel, enabled) }
        end

        private

        def lookup_kind(kind)
          Success(Registry.fetch(kind))
        rescue KeyError
          Failure(ServiceError.validation("Unknown notification kind: #{kind.inspect}"))
        end

        def validate_channel(kind_class, channel)
          if kind_class.supported_channels.include?(channel.to_sym)
            Success(kind_class)
          else
            Failure(ServiceError.validation("Kind #{kind_class.key} does not support channel #{channel.inspect}"))
          end
        end

        def persist(user_id, kind, channel, enabled)
          UserNotificationPreference.upsert(
            user_id: user_id,
            kind: kind,
            channel: channel,
            enabled: enabled
          )
          Success({ kind: kind.to_s, channel: channel.to_s, enabled: enabled })
        end
      end
    end
  end
end
