# frozen_string_literal: true

module Auth
  module Passkeys
    # Shared input validation for passkey registration and authentication completion.
    module ChallengeValidation
      def validate_challenge_inputs(challenge_token, credential, user_id: nil)
        if challenge_token.nil? || challenge_token.empty?
          return Failure(ServiceError.validation("Challenge token is required"))
        end

        if credential.nil? || credential.empty?
          return Failure(ServiceError.validation("Credential is required"))
        end

        decoded = Auth::Token.decode_webauthn_challenge(challenge_token, user_id: user_id)
        Success(decoded[:challenge])
      rescue JWT::DecodeError => e
        APP_LOGGER.warn { "[Auth::Passkeys] Challenge validation failed: #{e.class}" }
        Failure(ServiceError.unauthorized("Invalid or expired challenge"))
      end
    end
  end
end
