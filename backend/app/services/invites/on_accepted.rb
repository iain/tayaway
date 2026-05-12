# frozen_string_literal: true

module Invites
  # Tells the original inviter that their invite was accepted. Silent
  # when the invite carries no `invited_by` (older invites, or system-
  # generated ones).
  module OnAccepted
    class << self
      def call(invite:, invitee:)
        Notifications::Safely.deliver(context: "Invites::OnAccepted") do
          return unless invite.invited_by

          inviter = User.find(invite.invited_by)
          workspace = Workspace.find(invite.workspace_id)
          return unless inviter && workspace

          invitee_display = invitee.name || invitee.email.to_s

          Notifications::Dispatch.call(
            kind: :workspace_invite_accepted,
            user_id: inviter.id.to_s,
            workspace_id: invite.workspace_id.to_s,
            data: {
              email: inviter.email.to_s,
              recipient_name: inviter.name,
              invitee_name: invitee_display,
              workspace_name: workspace.name,
              workspace_url: FRONTEND_URL
            }
          )
        end
      end
    end
  end
end
