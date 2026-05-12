# frozen_string_literal: true

module Users
  # Sends an email-change confirmation to the OLD email address — that's
  # the security-critical surface, because if an attacker drove the
  # change the old inbox is what the legitimate owner still controls.
  # The in-app and push channels reach the user under the new email
  # regardless; only the email channel needs the old address.
  module OnEmailChanged
    class << self
      def call(user_id:, old_email:, new_email:)
        Notifications::Safely.deliver(context: "Users::OnEmailChanged") do
          user = User.find(user_id)
          Notifications::Dispatch.call(
            kind: :email_change_completed,
            user_id: user_id.to_s,
            data: {
              email: old_email,
              recipient_name: user&.name,
              old_email: old_email,
              new_email: new_email,
              session_url: "#{FRONTEND_URL}/settings/login"
            }
          )
        end
      end
    end
  end
end
