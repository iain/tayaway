# frozen_string_literal: true

module Auth
  module Passkeys
    module Rename
      class << self
        include Result::Methods

        def call(user_id:, passkey_id:, name:)
          validate_name(name)
            .bind { |valid_name| find_passkey(user_id, passkey_id, valid_name) }
            .bind { |params| update_name(params[:passkey], params[:name]) }
        end

        private

        def validate_name(name)
          stripped = name&.strip
          if stripped.nil? || stripped.empty?
            return Failure(ServiceError.validation("Name is required"))
          end

          if stripped.length > CompleteRegistration::MAX_NAME_LENGTH
            return Failure(ServiceError.validation("Name must be #{CompleteRegistration::MAX_NAME_LENGTH} characters or fewer"))
          end

          Success(stripped)
        end

        def find_passkey(user_id, passkey_id, name)
          passkey = PasskeyCredential.find(passkey_id)
          if passkey.nil? || passkey.user_id.to_s != user_id
            return Failure(ServiceError.not_found("Passkey not found"))
          end

          Success({ passkey: passkey, name: name })
        end

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
          Success({ passkey: updated.to_api_hash })
        rescue Sequel::Error => e
          APP_LOGGER.warn { "[Auth::Passkeys] Rename DB error: #{e.class}" }
          Failure(ServiceError.validation("Failed to rename passkey"))
        end
      end
    end
  end
end
