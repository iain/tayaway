# typed: true
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
      extend T::Sig
      include Result::Methods

      sig do
        params(session_id: String, user_id: UUID).returns(Result[T::Hash[Symbol, String], ServiceError])
      end
      def call(session_id:, user_id:)
        find_session(session_id).bind { |session| validate_ownership(session, user_id) }.bind { |session| destroy(session) }
      end

      private

      sig { params(session_id: String).returns(Result[Session, ServiceError]) }
      def find_session(session_id)
        session = Session.find_valid_by_id(session_id)

        if session
          T.cast(Success(session), Result[Session, ServiceError])
        else
          T.cast(Failure(ServiceError.not_found("Session not found")), Result[Session, ServiceError])
        end
      end

      sig { params(session: Session, user_id: UUID).returns(Result[Session, ServiceError]) }
      def validate_ownership(session, user_id)
        if session.user_id == user_id
          T.cast(Success(session), Result[Session, ServiceError])
        else
          T.cast(Failure(ServiceError.forbidden("Cannot delete another user's session")), Result[Session, ServiceError])
        end
      end

      sig { params(session: Session).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def destroy(session)
        DB[:sessions].where(id: session.id.to_s).delete
        T.cast(Success({ message: "Session ended successfully" }), Result[T::Hash[Symbol, String], ServiceError])
      end
    end
  end
end
