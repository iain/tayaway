# frozen_string_literal: true

module Auth
  module Passkeys
    module Delete
      class << self
        include Result::Methods

        def call(user_id:, passkey_id:)
          find_passkey(user_id, passkey_id)
            .bind { |passkey| delete_passkey(passkey) }
        end

        private

        def find_passkey(user_id, passkey_id)
          passkey = PasskeyCredential.find(passkey_id)
          if passkey.nil?
            return Failure(ServiceError.not_found("Passkey not found"))
          end

          if passkey.user_id.to_s != user_id
            APP_LOGGER.warn { "[Auth::Passkeys] User #{user_id} attempted to delete passkey #{passkey_id} owned by another user" }
            return Failure(ServiceError.forbidden("Not authorized"))
          end

          Success(passkey)
        end

        def delete_passkey(passkey)
          DB[:passkey_credentials].where(id: passkey.id.to_s).delete
          APP_LOGGER.info { "[Auth::Passkeys] Passkey #{passkey.id} deleted for user #{passkey.user_id}" }
          Success({ message: "Passkey deleted" })
        end
      end
    end
  end
end
