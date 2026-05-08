# frozen_string_literal: true

module Auth
  module Passkeys
    module BeginRegistration
      class << self
        MAX_PASSKEYS_PER_USER = 20

        def call(user_id:)
          find_user(user_id)
            .bind { |user| generate_options(user) }
        end

        private

        def find_user(user_id)
          user = User.find(user_id)
          if user
            Success(user)
          else
            Failure(ServiceError.not_found("User not found"))
          end
        end

        def generate_options(user)
          existing = PasskeyCredential.for_user(user.id)

          if existing.length >= MAX_PASSKEYS_PER_USER
            APP_LOGGER.warn { "[Auth::Passkeys] User #{user.id} reached max passkeys limit (#{MAX_PASSKEYS_PER_USER})" }
            return Failure(ServiceError.validation("Maximum number of passkeys reached"))
          end

          exclude = existing.map { |c| c.external_id }

          options = WebAuthn::Credential.options_for_create(
            user: {
              id: user.id.to_s,
              name: user.email.to_s,
              display_name: user.name || user.email.to_s
            },
            exclude: exclude,
            authenticator_selection: {
              resident_key: "preferred",
              user_verification: "preferred"
            },
            attestation: "indirect"
          )

          challenge_token = Auth::Token.encode_webauthn_challenge(challenge: options.challenge, user_id: user.id.to_s)

          Success({
            options: options.as_json,
            challengeToken: challenge_token
          }
                 )
        end
      end
    end
  end
end
