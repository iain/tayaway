# typed: true
# frozen_string_literal: true

module Auth
  module Passkeys
    # Shared input validation for passkey registration and authentication completion.
    module ChallengeValidation
      extend T::Sig
      include Result::Methods

      sig do
        params(
          challenge_token: T.nilable(String),
          credential: T.nilable(T::Hash[String, T.untyped]),
          user_id: T.nilable(String)
        ).returns(Result[String, ServiceError])
      end
      def validate_challenge_inputs(challenge_token, credential, user_id: nil)
        if challenge_token.nil? || challenge_token.empty?
          return T.cast(Failure(ServiceError.validation("Challenge token is required")), Result[String, ServiceError])
        end

        if credential.nil? || credential.empty?
          return T.cast(Failure(ServiceError.validation("Credential is required")), Result[String, ServiceError])
        end

        decoded = Auth::Token.decode_webauthn_challenge(challenge_token, user_id: user_id)
        T.cast(Success(decoded[:challenge]), Result[String, ServiceError])
      rescue JWT::DecodeError
        T.cast(Failure(ServiceError.unauthorized("Invalid or expired challenge")), Result[String, ServiceError])
      end
    end
  end
end
