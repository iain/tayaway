# frozen_string_literal: true

module Auth
  module Passkeys
    module BeginAuthentication
      class << self
        def call
          generate_options
        end

        private

        def generate_options
          options = WebAuthn::Credential.options_for_get(
            user_verification: "preferred"
          )

          challenge_token = Auth::Token.encode_webauthn_challenge(challenge: options.challenge)

          Success({
            options: options.as_json,
            challengeToken: challenge_token
          }
                 )
        rescue WebAuthn::Error => e
          APP_LOGGER.warn { "[Auth::Passkeys] Authentication options generation failed: #{e.class}" }
          Failure(ServiceError.validation("Failed to generate authentication options"))
        end
      end
    end
  end
end
