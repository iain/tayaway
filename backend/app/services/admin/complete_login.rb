# frozen_string_literal: true

module Admin
  # Passkey login for the admin site. Reuses the main app's WebAuthn
  # credentials (same RP ID), but authorization is the ADMIN_EMAILS
  # allowlist and the session lands in admin_sessions, not sessions.
  # No writes happen unless the user clears the allowlist check.
  module CompleteLogin
    class << self
      include Auth::Passkeys::ChallengeValidation

      def call(challenge_token:, credential:)
        Success()
          .bind { validate_challenge_inputs(challenge_token, credential) }
          .bind { |challenge| verify_credential(credential, challenge) }
          .bind { |verified| authorize_admin(verified) }
          .bind { |verified| create_session(verified) }
      end

      private

      def verify_credential(credential, challenge)
        webauthn_credential = WebAuthn::Credential.from_get(credential)

        stored = PasskeyCredential.find_by_external_id(webauthn_credential.id)
        unless stored
          return Failure(ServiceError.unauthorized("Passkey not recognized"))
        end

        webauthn_credential.verify(
          challenge,
          public_key: stored.public_key,
          sign_count: stored.sign_count
        )

        user = User.find(stored.user_id)
        unless user
          return Failure(ServiceError.unauthorized("User not found"))
        end

        Success({ user: user, stored: stored, sign_count: webauthn_credential.sign_count.to_i })
      rescue WebAuthn::Error => e
        APP_LOGGER.warn { "[Admin::CompleteLogin] Verification failed: #{e.class}" }
        Failure(ServiceError.unauthorized("Passkey authentication failed"))
      end

      def authorize_admin(verified)
        allowlist = APP_CONFIG.admin_emails.map(&:downcase)
        if allowlist.include?(verified[:user].email.to_s.downcase)
          Success(verified)
        else
          APP_LOGGER.warn { "[Admin::CompleteLogin] Non-admin login attempt by user #{verified[:user].id}" }
          Failure(ServiceError.forbidden("Not an admin"))
        end
      end

      # Mirrors Auth::Passkeys::CompleteAuthentication: sign-count bump and
      # session insert share a transaction, GREATEST prevents concurrent
      # logins from regressing the sign count.
      def create_session(verified)
        token = SecureRandom.hex(32)
        expires_at = Time.now + AdminSession::EXPIRY_SECONDS

        DB.transaction do
          DB[:passkey_credentials]
            .where(id: verified[:stored].id.to_s)
            .update(sign_count: Sequel.function(:GREATEST, :sign_count, verified[:sign_count]))

          DB[:admin_sessions].insert(
            user_id: verified[:user].id.to_s,
            token: Auth::Token.digest(token),
            expires_at: expires_at
          )
        end

        APP_LOGGER.info { "[Admin::CompleteLogin] Admin session created for user #{verified[:user].id}" }
        Success({ token: token, expires_at: expires_at, user_id: verified[:user].id.to_s })
      rescue Sequel::Error => e
        APP_LOGGER.warn { "[Admin::CompleteLogin] DB error: #{e.class}" }
        Failure(ServiceError.validation("Login failed"))
      end
    end
  end
end
