# typed: true
# frozen_string_literal: true

module Auth
  module Passkeys
    module CompleteRegistration
      class << self
        extend T::Sig
        include Result::Methods

        sig do
          params(
            user_id: String,
            challenge_token: T.nilable(String),
            credential: T.nilable(T::Hash[String, T.untyped]),
            name: T.nilable(String)
          ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
        def call(user_id:, challenge_token:, credential:, name: nil)
          validate_inputs(challenge_token, credential)
            .bind { |challenge| verify_credential(T.must(credential), challenge) }
            .bind { |webauthn_credential| store_credential(user_id, webauthn_credential, name) }
        end

        private

        sig do
          params(challenge_token: T.nilable(String), credential: T.nilable(T::Hash[String, T.untyped]))
            .returns(Result[String, ServiceError])
        end
        def validate_inputs(challenge_token, credential)
          if challenge_token.nil? || challenge_token.empty?
            return T.cast(Failure(ServiceError.validation("Challenge token is required")), Result[String, ServiceError])
          end

          if credential.nil? || credential.empty?
            return T.cast(Failure(ServiceError.validation("Credential is required")), Result[String, ServiceError])
          end

          decoded = Auth::Token.decode_webauthn_challenge(challenge_token)
          T.cast(Success(decoded[:challenge]), Result[String, ServiceError])
        rescue JWT::DecodeError
          T.cast(Failure(ServiceError.unauthorized("Invalid or expired challenge")), Result[String, ServiceError])
        end

        sig do
          params(credential: T::Hash[String, T.untyped], challenge: String)
            .returns(Result[WebAuthn::PublicKeyCredentialWithAttestation, ServiceError])
        end
        def verify_credential(credential, challenge)
          webauthn_credential = WebAuthn::Credential.from_create(credential)
          webauthn_credential.verify(challenge)
          T.cast(
            Success(webauthn_credential),
            Result[WebAuthn::PublicKeyCredentialWithAttestation, ServiceError]
          )
        rescue WebAuthn::Error => e
          APP_LOGGER.warn { "[Auth::Passkeys] Registration verification failed: #{e.class}" }
          T.cast(
            Failure(ServiceError.validation("Passkey verification failed")),
            Result[WebAuthn::PublicKeyCredentialWithAttestation, ServiceError]
          )
        end

        sig do
          params(
            user_id: String,
            webauthn_credential: WebAuthn::PublicKeyCredentialWithAttestation,
            name: T.nilable(String)
          ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
        def store_credential(user_id, webauthn_credential, name)
          aaguid = webauthn_credential.response.authenticator_data.aaguid
          device_name = name.nil? || name.strip.empty? ? lookup_device_name(aaguid) : name.strip

          id = SecureRandom.uuid
          now = Time.now

          DB[:passkey_credentials].insert(
            id: id,
            user_id: user_id,
            external_id: webauthn_credential.id.to_s,
            public_key: webauthn_credential.public_key.to_s,
            sign_count: webauthn_credential.sign_count.to_i,
            aaguid: aaguid&.to_s,
            name: device_name,
            created_at: now
          )

          passkey = PasskeyCredential.find(id)

          T.cast(Success({
            passkey: T.must(passkey).to_api_hash
          }
                        ), Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        sig { params(aaguid: T.nilable(String)).returns(T.nilable(String)) }
        def lookup_device_name(aaguid)
          return nil if aaguid.nil? || aaguid == "00000000-0000-0000-0000-000000000000"

          store = FidoMetadata::Store.new
          entry = store.fetch_entry(aaguid: aaguid)
          return nil unless entry

          statement = entry.metadata_statement
          statement&.description
        rescue StandardError => e
          APP_LOGGER.debug { "[Auth::Passkeys] FIDO metadata lookup failed for #{aaguid}: #{e.message}" }
          nil
        end
      end
    end
  end
end
