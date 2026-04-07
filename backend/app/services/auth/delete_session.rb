# frozen_string_literal: true

module Auth
  # Service to delete a specific session for a user.
  #
  # @example
  #   result = Auth::DeleteSession.call(session_id: "abc-123", user_id: user.id)
  #   result.success?  # => true
  #   result.value!    # => { message: "Session ended successfully" }
  module DeleteSession
    class << self
      include Dry::Monads[:result]

      def call(session_id:, user_id:)
        find_session(session_id).bind { |session| validate_ownership(session, user_id) }.bind { |session| destroy(session) }
      end

      private

      def find_session(session_id)
        session = Session.find_valid_by_id(session_id)

        if session
          Success(session)
        else
          Failure(ServiceError.not_found("Session not found"))
        end
      end

      def validate_ownership(session, user_id)
        if session.user_id == user_id
          Success(session)
        else
          Failure(ServiceError.forbidden("Cannot delete another user's session"))
        end
      end

      def destroy(session)
        DB[:sessions].where(id: session.id.to_s).delete
        Websocket::ConnectionManager.instance.close_sessions([session.id.to_s])
        APP_LOGGER.info { "[Auth::DeleteSession] Session #{session.id} deleted for user #{session.user_id}" }
        Success({ message: "Session ended successfully" })
      end
    end
  end
end
