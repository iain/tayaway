# typed: true
# frozen_string_literal: true

module Auth
  # Service to create a single-use WebSocket ticket.
  #
  # The ticket replaces passing the long-lived session token as a URL
  # query parameter. Instead, the frontend requests an ephemeral ticket
  # via the authenticated REST API, then connects the WebSocket with it.
  #
  # @example
  #   result = Auth::CreateWsTicket.call(auth_header: "Bearer abc123")
  #   result.success?  # => true
  #   result.value!    # => { ticket: "<jwt>" }
  module CreateWsTicket
    class << self
      extend T::Sig
      include Result::Methods

      sig { params(auth_header: T.nilable(String)).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def call(auth_header:)
        validate_auth_header(auth_header)
          .bind { |token| find_session(token) }
          .bind { |session| generate_ticket(session) }
      end

      private

      sig { params(auth_header: T.nilable(String)).returns(Result[String, ServiceError]) }
      def validate_auth_header(auth_header)
        if auth_header.nil? || auth_header.empty?
          T.cast(Failure(ServiceError.unauthorized("Authorization required")), Result[String, ServiceError])
        else
          T.cast(Success(auth_header.sub(/^Bearer\s+/, "")), Result[String, ServiceError])
        end
      end

      sig { params(token: String).returns(Result[Session, ServiceError]) }
      def find_session(token)
        session = Session.find_valid(token)
        if session
          T.cast(Success(session), Result[Session, ServiceError])
        else
          T.cast(Failure(ServiceError.unauthorized("Invalid or expired session")), Result[Session, ServiceError])
        end
      end

      sig { params(session: Session).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def generate_ticket(session)
        raw_token = SecureRandom.hex(32)
        now = Time.now
        expires_at = now + WsTicket::EXPIRY_SECONDS

        DB[:ws_tickets].insert(
          id: SecureRandom.uuid,
          user_id: session.user_id,
          token: Auth::Token.digest(raw_token),
          expires_at: expires_at,
          created_at: now
        )

        jwt = Auth::Token.encode_ws_ticket(token: raw_token)
        T.cast(Success({ ticket: jwt }), Result[T::Hash[Symbol, String], ServiceError])
      end
    end
  end
end
