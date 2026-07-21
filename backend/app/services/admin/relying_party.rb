# frozen_string_literal: true

module Admin
  # The admin site's own WebAuthn relying party. Its RP ID is the admin
  # host itself (not the apex shared with the main app), so admin passkeys
  # are scoped to the admin origin and dev works on plain localhost.
  module RelyingParty
    class << self
      def instance
        @_instance ||= WebAuthn::RelyingParty.new(
          allowed_origins: [APP_CONFIG.admin_origin.to_s],
          id: APP_CONFIG.admin_origin.host,
          name: "Tayaway admin",
          # Same reasoning as the global config: we don't restrict
          # authenticator models, so chain verification adds nothing.
          verify_attestation_statement: false
        )
      end
    end
  end
end
