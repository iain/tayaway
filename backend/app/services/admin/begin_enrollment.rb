# frozen_string_literal: true

module Admin
  # Passkey enrollment for the admin site. Open only while the credential
  # store is empty (first boot, still behind the edge's mTLS gate) or to a
  # logged-in operator adding another device.
  module BeginEnrollment
    class << self
      def call(authenticated:)
        Success()
          .bind { authorize(authenticated) }
          .bind { generate_options }
      end

      private

      def authorize(authenticated)
        if authenticated || State.db[:admin_credentials].empty?
          Success()
        else
          APP_LOGGER.warn { "[Admin::BeginEnrollment] Enrollment attempt while closed" }
          Failure(ServiceError.forbidden("Enrollment is closed"))
        end
      end

      def generate_options
        options = WebAuthn::Credential.options_for_create(
          # A single fixed identity: the admin site has exactly one
          # operator, devices are told apart by nickname.
          user: {
            id: "operator",
            name: "operator",
            display_name: "Tayaway operator"
          },
          exclude: State.db[:admin_credentials].select_map(:external_id),
          authenticator_selection: {
            resident_key: "preferred",
            user_verification: "preferred"
          },
          relying_party: RelyingParty.instance
        )

        Success({
          options: options.as_json,
          challengeToken: ChallengeToken.encode(challenge: options.challenge, purpose: "register")
        }
               )
      rescue WebAuthn::Error => e
        APP_LOGGER.warn { "[Admin::BeginEnrollment] Options generation failed: #{e.class}" }
        Failure(ServiceError.validation("Failed to generate enrollment options"))
      end
    end
  end
end
