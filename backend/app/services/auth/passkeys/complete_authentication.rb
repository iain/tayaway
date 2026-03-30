# typed: true
# frozen_string_literal: true

module Auth
  module Passkeys
    module CompleteAuthentication
      class << self
        extend T::Sig
        include Result::Methods
        include ChallengeValidation

        sig do
          params(
            challenge_token: T.nilable(String),
            credential: T.nilable(T::Hash[String, T.untyped]),
            ip: T.nilable(String),
            user_agent: T.nilable(String)
          ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
        def call(challenge_token:, credential:, ip: nil, user_agent: nil)
          validate_challenge_inputs(challenge_token, credential)
            .bind { |challenge| verify_and_create_session(T.must(credential), challenge, ip: ip, user_agent: user_agent) }
        end

        private

        sig do
          params(
            credential: T::Hash[String, T.untyped],
            challenge: String,
            ip: T.nilable(String),
            user_agent: T.nilable(String)
          ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
        def verify_and_create_session(credential, challenge, ip: nil, user_agent: nil)
          webauthn_credential = WebAuthn::Credential.from_get(credential)

          stored = PasskeyCredential.find_by_external_id(webauthn_credential.id)
          unless stored
            return T.cast(
              Failure(ServiceError.unauthorized("Passkey not recognized")),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
          end

          webauthn_credential.verify(
            challenge,
            public_key: stored.public_key,
            sign_count: stored.sign_count
          )

          user = User.find(stored.user_id)
          unless user
            return T.cast(
              Failure(ServiceError.unauthorized("User not found")),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
          end

          # Wrap sign_count update + session creation in a transaction.
          # Use GREATEST to prevent concurrent logins from regressing the sign count.
          new_sign_count = webauthn_credential.sign_count.to_i
          result = DB.transaction do
            DB[:passkey_credentials]
              .where(id: stored.id.to_s)
              .update(sign_count: Sequel.function(:GREATEST, :sign_count, new_sign_count))

            Auth::SessionCreator.create(stored.user_id.to_s, ip: ip, user_agent: user_agent)
          end

          APP_LOGGER.info { "[Auth::Passkeys] Session created for user #{stored.user_id} via passkey" }
          T.cast(Success(result), Result[T::Hash[Symbol, T.untyped], ServiceError])
        rescue WebAuthn::Error => e
          APP_LOGGER.warn { "[Auth::Passkeys] Authentication verification failed: #{e.class}" }
          T.cast(
            Failure(ServiceError.unauthorized("Passkey authentication failed")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        rescue Sequel::Error => e
          APP_LOGGER.warn { "[Auth::Passkeys] Authentication DB error: #{e.class}" }
          T.cast(
            Failure(ServiceError.validation("Authentication failed")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end
      end
    end
  end
end
