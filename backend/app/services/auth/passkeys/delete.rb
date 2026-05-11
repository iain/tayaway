# frozen_string_literal: true

module Auth
  module Passkeys
    module Delete
      class << self
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
          notify_passkey_removed(passkey)
          Success({ message: "Passkey deleted" })
        end

        def notify_passkey_removed(passkey)
          Notifications::Safely.deliver(context: "Auth::Passkeys") do
            user = User.find(passkey.user_id)
            return unless user

            Notifications::Dispatch.call(
              kind: :passkey_changed,
              user_id: passkey.user_id.to_s,
              data: {
                email: user.email.to_s,
                recipient_name: user.name,
                action: "removed",
                passkey_name: passkey.name,
                session_url: "#{ENV.fetch("FRONTEND_URL", "https://tayaway.nl")}/settings/login"
              }
            )
          end
        end
      end
    end
  end
end
