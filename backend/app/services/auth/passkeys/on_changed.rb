# frozen_string_literal: true

module Auth
  module Passkeys
    # Sent when a passkey is registered on or removed from an account.
    # The `action: "added"|"removed"` field switches the kind's copy; both
    # sides of the change go through one handler because the user-facing
    # decision is "tell me when my credential set changes" — opting into
    # one direction without the other doesn't reflect a real preference.
    module OnChanged
      class << self
        def call(user_id:, passkey_name:, action:)
          Notifications::Safely.deliver(context: "Auth::Passkeys::OnChanged") do
            user = User.find(user_id)
            return unless user

            Notifications::Dispatch.call(
              kind: :passkey_changed,
              user_id: user_id.to_s,
              data: {
                email: user.email.to_s,
                recipient_name: user.name,
                action: action,
                passkey_name: passkey_name,
                session_url: APP_CONFIG.frontend_url.path("/settings/login")
              }
            )
          end
        end
      end
    end
  end
end
