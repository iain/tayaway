# typed: true
# frozen_string_literal: true

module Auth
  module Passkeys
    module BeginRegistration
      class << self
        extend T::Sig
        include Result::Methods

        MAX_PASSKEYS_PER_USER = 20

        sig { params(user_id: String).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
        def call(user_id:)
          find_user(user_id)
            .bind { |user| generate_options(user) }
        end

        private

        sig { params(user_id: String).returns(Result[User, ServiceError]) }
        def find_user(user_id)
          user = User.find(user_id)
          if user
            T.cast(Success(user), Result[User, ServiceError])
          else
            T.cast(Failure(ServiceError.not_found("User not found")), Result[User, ServiceError])
          end
        end

        sig { params(user: User).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
        def generate_options(user)
          existing = PasskeyCredential.for_user(user.id)

          if existing.length >= MAX_PASSKEYS_PER_USER
            return T.cast(
              Failure(ServiceError.validation("Maximum number of passkeys reached")),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
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
            }
          )

          challenge_token = Auth::Token.encode_webauthn_challenge(challenge: options.challenge)

          T.cast(Success({
            options: options.as_json,
            challengeToken: challenge_token
          }
                        ), Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end
      end
    end
  end
end
