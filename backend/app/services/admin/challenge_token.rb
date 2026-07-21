# frozen_string_literal: true

module Admin
  # Admin-scoped WebAuthn challenge JWTs. Signed with the same app secret
  # as the main app's, so the typ values must stay distinct — they are what
  # keeps a main-app challenge token from being replayed against the admin
  # endpoints (and vice versa).
  module ChallengeToken
    EXPIRY_SECONDS = 300 # 5 minutes, mirrors Auth::Token

    class << self
      def encode(challenge:, purpose:)
        payload = {
          challenge: challenge,
          typ: "admin_webauthn_#{purpose}",
          exp: (Time.now + EXPIRY_SECONDS).to_i
        }
        JWT.encode(payload, APP_CONFIG.app_secret, "HS256")
      end

      # Raises JWT::DecodeError on any mismatch; callers rescue into a
      # Failure so the chain shape stays uniform.
      def decode(jwt, purpose:)
        payload = JWT.decode(jwt, APP_CONFIG.app_secret, true, algorithm: "HS256").first
        unless payload["typ"] == "admin_webauthn_#{purpose}"
          raise JWT::DecodeError, "Invalid token type"
        end

        payload["challenge"]
      end
    end
  end
end
