# frozen_string_literal: true

module Admin
  # Passkey login for the admin site. Fully self-contained: credentials and
  # sessions live in the admin's own store (Admin::State), so operator
  # login never touches — and never depends on — the main database.
  module CompleteLogin
    class << self
      def call(challenge_token:, credential:)
        Success()
          .bind { validate_inputs(challenge_token, credential) }
          .bind { |challenge| verify_credential(credential, challenge) }
          .bind { |verified| create_session(verified) }
      end

      private

      def validate_inputs(challenge_token, credential)
        if challenge_token.nil? || challenge_token.empty?
          Failure(ServiceError.validation("Challenge token is required"))
        elsif credential.nil? || credential.empty?
          Failure(ServiceError.validation("Credential is required"))
        else
          Success(ChallengeToken.decode(challenge_token, purpose: "authenticate"))
        end
      rescue JWT::DecodeError => e
        APP_LOGGER.warn { "[Admin::CompleteLogin] Challenge validation failed: #{e.class}" }
        Failure(ServiceError.unauthorized("Invalid or expired challenge"))
      end

      def verify_credential(credential, challenge)
        webauthn_credential = WebAuthn::Credential.from_get(credential, relying_party: RelyingParty.instance)

        stored = State.db[:admin_credentials].where(external_id: webauthn_credential.id.to_s).first
        unless stored
          return Failure(ServiceError.unauthorized("Passkey not recognized"))
        end

        webauthn_credential.verify(
          challenge,
          public_key: stored[:public_key],
          sign_count: stored[:sign_count]
        )

        Success({ stored: stored, sign_count: webauthn_credential.sign_count.to_i })
      rescue WebAuthn::Error => e
        APP_LOGGER.warn { "[Admin::CompleteLogin] Verification failed: #{e.class}" }
        Failure(ServiceError.unauthorized("Passkey authentication failed"))
      end

      def create_session(verified)
        token = SecureRandom.hex(32)
        now = Time.now
        expires_at = now + AdminSession::EXPIRY_SECONDS
        db = State.db

        db.transaction do
          # SQLite's scalar max() is the GREATEST here: concurrent logins
          # must not regress the sign counter.
          db[:admin_credentials]
            .where(id: verified[:stored][:id])
            .update(
              sign_count: Sequel.function(:max, :sign_count, verified[:sign_count]),
              last_used_at: now
            )

          # Opportunistic sweep — the admin process has no jobs worker, so
          # expired sessions are pruned on the one write path they share.
          db[:admin_sessions].where(Sequel[:expires_at] <= now).delete
          db[:admin_sessions].insert(
            token: Auth::Token.digest(token),
            credential_id: verified[:stored][:id],
            created_at: now,
            expires_at: expires_at
          )
        end

        APP_LOGGER.info { "[Admin::CompleteLogin] Admin session created (credential #{verified[:stored][:id]})" }
        Success({ token: token, expires_at: expires_at })
      rescue Sequel::Error => e
        APP_LOGGER.warn { "[Admin::CompleteLogin] DB error: #{e.class}" }
        Failure(ServiceError.validation("Login failed"))
      end
    end
  end
end
