# typed: true
# frozen_string_literal: true

module Auth
  module Passkeys
    module BeginAuthentication
      class << self
        extend T::Sig
        include Result::Methods

        sig { returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
        def call
          generate_options
        end

        private

        sig { returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
        def generate_options
          options = WebAuthn::Credential.options_for_get(
            user_verification: "preferred"
          )

          challenge_token = Auth::Token.encode_webauthn_challenge(challenge: options.challenge)

          T.cast(Success({
            options: options.as_json,
            challengeToken: challenge_token
          }
                        ), Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        rescue WebAuthn::Error => e
          APP_LOGGER.warn { "[Auth::Passkeys] Authentication options generation failed: #{e.class}" }
          T.cast(
            Failure(ServiceError.validation("Failed to generate authentication options")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end
      end
    end
  end
end
