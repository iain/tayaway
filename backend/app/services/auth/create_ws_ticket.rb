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
  #   result = Auth::CreateWsTicket.call(user_id: "uuid")
  #   result.success?  # => true
  #   result.value!    # => { ticket: "<jwt>" }
  module CreateWsTicket
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(user_id: T.any(String, UUID), session_id: T.any(String, UUID)).returns(Result[T::Hash[Symbol, String], ServiceError])
      end
      def call(user_id:, session_id:)
        generate_ticket(user_id, session_id)
      end

      private

      sig do
        params(user_id: T.any(String, UUID), session_id: T.any(String, UUID)).returns(Result[T::Hash[Symbol, String], ServiceError])
      end
      def generate_ticket(user_id, session_id)
        raw_token = SecureRandom.hex(32)
        now = Time.now
        expires_at = now + WsTicket::EXPIRY_SECONDS

        DB[:ws_tickets].insert(
          id: SecureRandom.uuid,
          user_id: user_id,
          session_id: session_id,
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
