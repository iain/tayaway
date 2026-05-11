# frozen_string_literal: true

module Invites
  # Fires the workspace_invite notification at the invitee's email. Used
  # by both `Invites::Create` (first send) and `Invites::Remind` (resend);
  # the user-facing notification is the same in either case — "here's a
  # link to join this workspace" — and the recipient doesn't need to
  # distinguish the two.
  module OnSent
    class << self
      def call(email:, invite_link:, workspace_id:, name: nil)
        Notifications::Safely.deliver(context: "Invites::OnSent") do
          workspace = Workspace.find(workspace_id)
          workspace_name = workspace ? workspace.name : "Tayaway"

          Notifications::Dispatch.call(
            kind: :workspace_invite,
            user_id: User.find_by_email(email)&.id&.to_s,
            workspace_id: workspace_id.to_s,
            data: {
              email: email,
              invite_link: invite_link,
              workspace_name: workspace_name,
              name: name
            }
          )
        end
      end
    end
  end
end
