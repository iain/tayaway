# typed: true
# frozen_string_literal: true

module Auth
  module Passkeys
    module CompleteRegistration
      MAX_NAME_LENGTH = 100

      class << self
        extend T::Sig
        include Result::Methods
        include ChallengeValidation

        sig do
          params(
            user_id: String,
            challenge_token: T.nilable(String),
            credential: T.nilable(T::Hash[String, T.untyped]),
            name: T.nilable(String)
          ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
        def call(user_id:, challenge_token:, credential:, name: nil)
          validate_challenge_inputs(challenge_token, credential, user_id: user_id)
            .bind { |challenge| verify_credential(T.must(credential), challenge) }
            .bind { |webauthn_credential| store_credential(user_id, webauthn_credential, name) }
        end

        private

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
          device_name = device_name&.slice(0, MAX_NAME_LENGTH)

          id = SecureRandom.uuid
          now = Time.now

          DB.transaction do
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
          end

          passkey = PasskeyCredential.new(
            id: UUID.new(id),
            user_id: UUID.new(user_id),
            external_id: webauthn_credential.id.to_s,
            public_key: webauthn_credential.public_key.to_s,
            sign_count: webauthn_credential.sign_count.to_i,
            aaguid: aaguid&.to_s,
            name: device_name,
            created_at: now
          )

          APP_LOGGER.info { "[Auth::Passkeys] Passkey #{id} registered for user #{user_id}" }
          T.cast(Success({ passkey: passkey.to_api_hash }), Result[T::Hash[Symbol, T.untyped], ServiceError])
        rescue Sequel::Error => e
          APP_LOGGER.warn { "[Auth::Passkeys] Registration DB error: #{e.class}" }
          T.cast(
            Failure(ServiceError.validation("Failed to store passkey")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        sig { returns(FidoMetadata::Store) }
        def fido_store
          @_fido_store ||= FidoMetadata::Store.new
        end

        sig { params(aaguid: T.nilable(String)).returns(T.nilable(String)) }
        def lookup_device_name(aaguid)
          return nil if aaguid.nil? || aaguid == "00000000-0000-0000-0000-000000000000"

          entry = fido_store.fetch_entry(aaguid: aaguid)
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
