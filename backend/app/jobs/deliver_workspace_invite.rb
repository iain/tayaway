# frozen_string_literal: true

module Jobs
  class DeliverWorkspaceInvite < Base
    def call(email:, invite_link:, workspace_name:, name: nil)
      Mailers::WorkspaceInvite.perform_delivery(
        email: email,
        invite_link: invite_link,
        workspace_name: workspace_name,
        name: name
      )
    end
  end
end
