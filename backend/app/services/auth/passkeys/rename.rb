# typed: true
# frozen_string_literal: true

module Auth
  module Passkeys
    module Rename
      MAX_NAME_LENGTH = 100

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
            .bind { |params| update_name(params[:passkey_id], params[:name]) }
        end

        private

        sig { params(name: T.nilable(String)).returns(Result[String, ServiceError]) }
        def validate_name(name)
          stripped = name&.strip
          if stripped.nil? || stripped.empty?
            return T.cast(Failure(ServiceError.validation("Name is required")), Result[String, ServiceError])
          end

          if stripped.length > MAX_NAME_LENGTH
            return T.cast(
              Failure(ServiceError.validation("Name must be #{MAX_NAME_LENGTH} characters or fewer")),
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

          T.cast(Success({ passkey_id: passkey_id, name: name }), Result[T::Hash[Symbol, T.untyped], ServiceError])
        end

        sig { params(passkey_id: String, name: String).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
        def update_name(passkey_id, name)
          DB[:passkey_credentials].where(id: passkey_id).update(name: name)
          updated = PasskeyCredential.find(passkey_id)
          APP_LOGGER.info { "[Auth::Passkeys] Passkey #{passkey_id} renamed" }
          T.cast(Success({ passkey: T.must(updated).to_api_hash }), Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
      end
    end
  end
end
