# frozen_string_literal: true

module Notifications
  module Preferences
    # Reverses a Silence by deleting every override row for the (user, kind)
    # pair, returning the kind to its default channel set. Used by the
    # bell's "Undo" flow when a user clicks "Stop sending me these" and
    # then changes their mind seconds later.
    #
    # Trade-off: any pre-existing custom overrides for this kind are also
    # cleared. Acceptable because Silence sets every configurable channel
    # to off — undoing it back to "exactly the prior state" would need a
    # snapshot, and users reaching for Undo within the toast window almost
    # always meant "restore defaults", not "reapply my power-user tweaks".
    module Unsilence
      class << self
        def call(user_id:, kind:)
          Success()
            .bind { lookup_kind(kind) }
            .bind { |kind_class| clear(user_id, kind_class) }
        end

        private

        def lookup_kind(kind)
          Success(Registry.fetch(kind))
        rescue KeyError
          Failure(ServiceError.validation("Unknown notification kind: #{kind.inspect}"))
        end

        def clear(user_id, kind_class)
          DB[:user_notification_preferences]
            .where(user_id: user_id, kind: kind_class.key.to_s)
            .delete
          Success({ kind: kind_class.key.to_s })
        end
      end
    end
  end
end
