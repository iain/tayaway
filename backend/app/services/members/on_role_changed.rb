# frozen_string_literal: true

module Members
  # Sent to a member whose workspace role just changed. Security-relevant
  # — promotions and demotions are exactly the kind of access change a
  # user wants to be aware of, so the kind keeps email on by default.
  module OnRoleChanged
    class << self
      def call(member:, old_role:, new_role:)
        Notifications::Safely.deliver(context: "Members::OnRoleChanged") do
          user = User.find(member.user_id)
          workspace = Workspace.find(member.workspace_id)
          return unless user && workspace

          Notifications::Dispatch.call(
            kind: :member_role_changed,
            user_id: member.user_id.to_s,
            workspace_id: member.workspace_id.to_s,
            data: {
              email: user.email.to_s,
              recipient_name: user.name,
              workspace_name: workspace.name,
              old_role: old_role,
              new_role: new_role,
              workspace_url: APP_CONFIG.frontend_url
            }
          )
        end
      end
    end
  end
end
