# frozen_string_literal: true

module Invites
  # Service to cancel (delete) a pending workspace invitation.
  module Cancel
    class << self
      include Dry::Monads[:result]

      def call(invite_id:, workspace_id:)
        find_invite(invite_id, workspace_id)
          .bind { |invite| delete_invite(invite) }
      end

      private

      def find_invite(invite_id, workspace_id)
        if invite_id.nil? || invite_id.empty?
          return Failure(ServiceError.validation("Invite ID is required"))
        end

        invite = WorkspaceInvite.find(invite_id)

        if invite.nil?
          return Failure(ServiceError.not_found("Invitation not found"))
        end

        if invite.workspace_id.to_s != workspace_id.to_s
          return Failure(ServiceError.not_found("Invitation not found"))
        end

        if invite.accepted_at
          return Failure(ServiceError.validation("This invitation has already been accepted"))
        end

        Success(invite)
      end

      def delete_invite(invite)
        invite_id = invite.id
        workspace_id = invite.workspace_id

        DB.transaction do
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "workspace_invite", object_id: invite_id)
          DB[:workspace_invites].where(id: invite_id).delete
          Broadcaster.object_deleted("workspace_invite", invite_id, workspace_id: workspace_id.to_s)
        end

        APP_LOGGER.info { "[Invites::Cancel] Invite #{invite_id} cancelled in workspace #{workspace_id}" }
        Success({ deleted: [{ objectType: "workspaceInvite", id: invite_id.to_s }] })
      end
    end
  end
end
