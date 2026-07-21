# frozen_string_literal: true

module Admin
  # Second half of admin passkey enrollment. The empty-store check runs
  # again inside the insert transaction: two first-boot tabs can both pass
  # BeginEnrollment, only one may land a credential.
  module CompleteEnrollment
    MAX_NICKNAME_LENGTH = 100

    class << self
      def call(challenge_token:, credential:, nickname:, authenticated:)
        Success()
          .bind { validate_inputs(challenge_token, credential) }
          .bind { |challenge| verify_credential(credential, challenge) }
          .bind { |webauthn_credential| store_credential(webauthn_credential, nickname, authenticated) }
      end

      private

      def validate_inputs(challenge_token, credential)
        if challenge_token.nil? || challenge_token.empty?
          Failure(ServiceError.validation("Challenge token is required"))
        elsif credential.nil? || credential.empty?
          Failure(ServiceError.validation("Credential is required"))
        else
          Success(ChallengeToken.decode(challenge_token, purpose: "register"))
        end
      rescue JWT::DecodeError => e
        APP_LOGGER.warn { "[Admin::CompleteEnrollment] Challenge validation failed: #{e.class}" }
        Failure(ServiceError.unauthorized("Invalid or expired challenge"))
      end

      def verify_credential(credential, challenge)
        webauthn_credential = WebAuthn::Credential.from_create(credential, relying_party: RelyingParty.instance)
        webauthn_credential.verify(challenge)
        Success(webauthn_credential)
      rescue WebAuthn::Error => e
        APP_LOGGER.warn { "[Admin::CompleteEnrollment] Verification failed: #{e.class}" }
        Failure(ServiceError.validation("Passkey verification failed"))
      end

      def store_credential(webauthn_credential, nickname, authenticated)
        name = nickname.to_s.strip
        name = "Passkey" if name.empty?
        name = name.slice(0, MAX_NICKNAME_LENGTH)

        db = State.db
        inserted = nil
        db.transaction do
          if authenticated || db[:admin_credentials].empty?
            inserted = db[:admin_credentials].insert(
              external_id: webauthn_credential.id.to_s,
              public_key: webauthn_credential.public_key.to_s,
              sign_count: webauthn_credential.sign_count.to_i,
              nickname: name,
              created_at: Time.now
            )
          end
        end

        if inserted
          APP_LOGGER.info { "[Admin::CompleteEnrollment] Enrolled admin passkey #{inserted} (#{name})" }
          Success({ id: inserted, nickname: name })
        else
          APP_LOGGER.warn { "[Admin::CompleteEnrollment] Enrollment attempt while closed" }
          Failure(ServiceError.forbidden("Enrollment is closed"))
        end
      rescue Sequel::Error => e
        APP_LOGGER.warn { "[Admin::CompleteEnrollment] DB error: #{e.class}" }
        Failure(ServiceError.validation("Failed to store passkey"))
      end
    end
  end
end
