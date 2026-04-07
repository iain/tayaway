# frozen_string_literal: true

module Auth
  # Service to consume a single-use WebSocket ticket during WS handshake.
  #
  # Decodes the JWT, HMAC-hashes the raw token, looks up the ticket in DB,
  # marks it as used, and returns the user_id and session_id.
  #
  # @example
  #   result = Auth::ConsumeWsTicket.call(ticket_jwt: "<jwt>")
  #   result.success?  # => true
  #   result.value!    # => { user_id: UUID("..."), session_id: "..." }
  module ConsumeWsTicket
    class << self
      include Dry::Monads[:result]

      def call(ticket_jwt:)
        decode_jwt(ticket_jwt)
          .bind { |raw_token| claim_ticket(raw_token) }
      end

      private

      def decode_jwt(jwt)
        if jwt.nil? || jwt.empty?
          return Failure(ServiceError.unauthorized("Missing ticket"))
        end

        decoded = Auth::Token.decode_ws_ticket(jwt)
        Success(decoded[:token])
      rescue JWT::DecodeError
        Failure(ServiceError.unauthorized("Invalid or expired ticket"))
      end

      # Atomically find and mark the ticket as used in a single UPDATE.
      # This prevents race conditions where two concurrent handshakes
      # could both consume the same ticket.
      def claim_ticket(raw_token)
        hashed = Auth::Token.digest(raw_token)
        now = Time.now

        invalid_ticket = Failure(ServiceError.unauthorized("Invalid or expired ticket"))

        ticket = DB[:ws_tickets]
                 .where(token: hashed, used_at: nil)
                 .where(Sequel[:expires_at] > now)
                 .returning(:session_id)
                 .update(used_at: now)
                 .first

        return invalid_ticket if ticket.nil?

        session_id = ticket[:session_id].to_s
        user_id = DB[:sessions].where(id: session_id).get(:user_id)

        return invalid_ticket if user_id.nil?

        Success({ user_id: UUID.new(user_id), session_id: session_id })
      end
    end
  end
end
