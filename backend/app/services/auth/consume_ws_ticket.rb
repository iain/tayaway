# typed: true
# frozen_string_literal: true

module Auth
  # Service to consume a single-use WebSocket ticket during WS handshake.
  #
  # Decodes the JWT, HMAC-hashes the raw token, looks up the ticket in DB,
  # marks it as used, and returns the user_id.
  #
  # @example
  #   result = Auth::ConsumeWsTicket.call(ticket_jwt: "<jwt>")
  #   result.success?  # => true
  #   result.value!    # => { user_id: UUID("...") }
  module ConsumeWsTicket
    class << self
      extend T::Sig
      include Result::Methods

      sig { params(ticket_jwt: T.nilable(String)).returns(Result[T::Hash[Symbol, UUID], ServiceError]) }
      def call(ticket_jwt:)
        decode_jwt(ticket_jwt)
          .bind { |raw_token| claim_ticket(raw_token) }
      end

      private

      sig { params(jwt: T.nilable(String)).returns(Result[String, ServiceError]) }
      def decode_jwt(jwt)
        if jwt.nil? || jwt.empty?
          return T.cast(Failure(ServiceError.unauthorized("Missing ticket")), Result[String, ServiceError])
        end

        decoded = Auth::Token.decode_ws_ticket(jwt)
        T.cast(Success(T.must(decoded[:token])), Result[String, ServiceError])
      rescue JWT::DecodeError
        T.cast(Failure(ServiceError.unauthorized("Invalid or expired ticket")), Result[String, ServiceError])
      end

      # Atomically find and mark the ticket as used in a single UPDATE.
      # This prevents race conditions where two concurrent handshakes
      # could both consume the same ticket.
      sig { params(raw_token: String).returns(Result[T::Hash[Symbol, UUID], ServiceError]) }
      def claim_ticket(raw_token)
        hashed = Auth::Token.digest(raw_token)
        now = Time.now

        ticket = DB[:ws_tickets]
                 .where(token: hashed, used_at: nil)
                 .where(Sequel[:expires_at] > now)
                 .returning(:user_id)
                 .update(used_at: now)
                 .first

        if ticket
          T.cast(Success({ user_id: UUID.new(ticket[:user_id]) }), Result[T::Hash[Symbol, UUID], ServiceError])
        else
          T.cast(Failure(ServiceError.unauthorized("Invalid or expired ticket")), Result[T::Hash[Symbol, UUID], ServiceError])
        end
      end
    end
  end
end
