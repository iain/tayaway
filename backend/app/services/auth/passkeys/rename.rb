# typed: true
# frozen_string_literal: true

module Auth
  module Passkeys
    module Rename
      class << self
        extend T::Sig
        include Result::Methods

        sig do
          params(user_id: String, passkey_id: String, name: T.nilable(String))
            .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
        def call(user_id:, passkey_id:, name:)
          validate_name(name)
            .bind { |valid_name| find_passkey(user_id, passkey_id, valid_name) }
            .bind { |params| update_name(params[:passkey], params[:name]) }
        end

        private

        sig { params(name: T.nilable(String)).returns(Result[String, ServiceError]) }
        def validate_name(name)
          stripped = name&.strip
          if stripped.nil? || stripped.empty?
            return T.cast(Failure(ServiceError.validation("Name is required")), Result[String, ServiceError])
          end

          if stripped.length > CompleteRegistration::MAX_NAME_LENGTH
            return T.cast(
              Failure(ServiceError.validation("Name must be #{CompleteRegistration::MAX_NAME_LENGTH} characters or fewer")),
              Result[String, ServiceError]
            )
          end

          T.cast(Success(stripped), Result[String, ServiceError])
        end

        sig do
          params(user_id: String, passkey_id: String, name: String)
            .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
        def find_passkey(user_id, passkey_id, name)
          passkey = PasskeyCredential.find(passkey_id)
          if passkey.nil? || passkey.user_id.to_s != user_id
            return T.cast(
              Failure(ServiceError.not_found("Passkey not found")),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
          end

          T.cast(Success({ passkey: passkey, name: name }), Result[T::Hash[Symbol, T.untyped], ServiceError])
        end

        sig { params(passkey: PasskeyCredential, name: String).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
        def update_name(passkey, name)
          DB[:passkey_credentials].where(id: passkey.id.to_s).update(name: name)

          # Build updated model from known values — avoids an extra SELECT
          updated = PasskeyCredential.new(
            id: passkey.id,
            user_id: passkey.user_id,
            external_id: passkey.external_id,
            public_key: passkey.public_key,
            sign_count: passkey.sign_count,
            aaguid: passkey.aaguid,
            name: name,
            created_at: passkey.created_at
          )

          APP_LOGGER.info { "[Auth::Passkeys] Passkey #{passkey.id} renamed" }
          T.cast(Success({ passkey: updated.to_api_hash }), Result[T::Hash[Symbol, T.untyped], ServiceError])
        rescue Sequel::Error => e
          APP_LOGGER.warn { "[Auth::Passkeys] Rename DB error: #{e.class}" }
          T.cast(
            Failure(ServiceError.validation("Failed to rename passkey")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end
      end
    end
  end
end
