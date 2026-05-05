# frozen_string_literal: true

module Jobs
  class DeliverWorkspaceInvite < Base
    def initialize(email:, invite_link:, workspace_name:, name: nil)
      super()
      @email = email
      @invite_link = invite_link
      @workspace_name = workspace_name
      @name = name
    end

    def call
      Mailers::WorkspaceInvite.deliver_now(
        email: @email,
        invite_link: @invite_link,
        workspace_name: @workspace_name,
        name: @name
      )
    end
  end
end
