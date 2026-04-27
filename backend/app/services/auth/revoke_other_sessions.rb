# frozen_string_literal: true

module Auth
  # Service to revoke all sessions for a user except the current one.
  #
  # @example
  #   result = Auth::RevokeOtherSessions.call(user_id: user.id, current_session_id: session.id)
  #   result.success?  # => true
  #   result.value!    # => { message: "All other sessions have been revoked" }
  module RevokeOtherSessions
    class << self
      def call(user_id:, current_session_id:)
        deleted_ids = DB[:sessions]
                      .where(user_id: user_id.to_s)
                      .exclude(id: current_session_id.to_s)
                      .returning(:id)
                      .delete
                      .map { |row| row[:id] }

        Websocket::ConnectionManager.instance.close_sessions(deleted_ids)
        APP_LOGGER.info { "[Auth::RevokeOtherSessions] Revoked #{deleted_ids.size} sessions for user #{user_id}" }

        Success({ message: "All other sessions have been revoked" })
      end
    end
  end
end
