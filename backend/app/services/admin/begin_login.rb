# frozen_string_literal: true

module Admin
  # First half of admin passkey login, against the admin site's own
  # relying party and credential store (doc/admin.md).
  module BeginLogin
    class << self
      def call
        options = WebAuthn::Credential.options_for_get(
          user_verification: "preferred",
          relying_party: RelyingParty.instance
        )

        Success({
          options: options.as_json,
          challengeToken: ChallengeToken.encode(challenge: options.challenge, purpose: "authenticate")
        }
               )
      rescue WebAuthn::Error => e
        APP_LOGGER.warn { "[Admin::BeginLogin] Options generation failed: #{e.class}" }
        Failure(ServiceError.validation("Failed to generate authentication options"))
      end
    end
  end
end
