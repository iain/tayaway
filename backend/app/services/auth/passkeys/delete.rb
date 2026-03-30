# typed: true
# frozen_string_literal: true

module Auth
  module Passkeys
    module Delete
      class << self
        extend T::Sig
        include Result::Methods

        sig { params(user_id: String, passkey_id: String).returns(Result[T::Hash[Symbol, String], ServiceError]) }
        def call(user_id:, passkey_id:)
          find_passkey(user_id, passkey_id)
            .bind { |passkey| delete_passkey(passkey) }
        end

        private

        sig { params(user_id: String, passkey_id: String).returns(Result[PasskeyCredential, ServiceError]) }
        def find_passkey(user_id, passkey_id)
          passkey = PasskeyCredential.find(passkey_id)
          if passkey.nil?
            return T.cast(Failure(ServiceError.not_found("Passkey not found")), Result[PasskeyCredential, ServiceError])
          end

          if passkey.user_id.to_s != user_id
            return T.cast(Failure(ServiceError.forbidden("Not authorized")), Result[PasskeyCredential, ServiceError])
          end

          T.cast(Success(passkey), Result[PasskeyCredential, ServiceError])
        end

        sig { params(passkey: PasskeyCredential).returns(Result[T::Hash[Symbol, String], ServiceError]) }
        def delete_passkey(passkey)
          DB[:passkey_credentials].where(id: passkey.id.to_s).delete
          APP_LOGGER.info { "[Auth::Passkeys] Passkey #{passkey.id} deleted for user #{passkey.user_id}" }
          T.cast(Success({ message: "Passkey deleted" }), Result[T::Hash[Symbol, String], ServiceError])
        end
      end
    end
  end
end
