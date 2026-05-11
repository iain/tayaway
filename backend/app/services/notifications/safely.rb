# frozen_string_literal: true

module Notifications
  # Wraps a notification-dispatch side effect so a failure can't take down
  # the underlying flow that triggered it (e.g. a passkey deletion must
  # not roll back because the change-alert email couldn't be sent).
  #
  # Behaviour split by environment is deliberate: in production we log
  # and continue, because losing one notification is far better than
  # losing the user's primary action; in test mode we re-raise so spec
  # failures aren't silently masked when notification wiring breaks.
  module Safely
    class << self
      def deliver(context:)
        yield
      rescue StandardError => e
        APP_LOGGER.error { "[#{context}] notification dispatch failed: #{e.class} - #{e.message}" }
        raise if APP_ENV == "test"
      end
    end
  end
end
