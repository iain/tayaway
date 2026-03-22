# typed: true
# frozen_string_literal: true

module Invites
  # Service to cancel (delete) a pending workspace invitation.
  module Cancel
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          invite_id: T.nilable(String),
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(invite_id:, workspace_id:)
        find_invite(invite_id, workspace_id)
          .bind { |invite| delete_invite(invite) }
      end

      private

      sig { params(invite_id: T.nilable(String), workspace_id: T.any(String, UUID)).returns(Result[WorkspaceInvite, ServiceError]) }
      def find_invite(invite_id, workspace_id)
        if invite_id.nil? || invite_id.empty?
          return T.cast(Failure(ServiceError.validation("Invite ID is required")), Result[WorkspaceInvite, ServiceError])
        end

        invite = WorkspaceInvite.find(invite_id)

        if invite.nil?
          return T.cast(Failure(ServiceError.not_found("Invitation not found")), Result[WorkspaceInvite, ServiceError])
        end

        if invite.workspace_id.to_s != workspace_id.to_s
          return T.cast(Failure(ServiceError.not_found("Invitation not found")), Result[WorkspaceInvite, ServiceError])
        end

        if invite.accepted_at
          return T.cast(Failure(ServiceError.validation("This invitation has already been accepted")), Result[WorkspaceInvite, ServiceError])
        end

        T.cast(Success(invite), Result[WorkspaceInvite, ServiceError])
      end

      sig { params(invite: WorkspaceInvite).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def delete_invite(invite)
        invite_id = invite.id
        workspace_id = invite.workspace_id

        DB.transaction do
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "workspace_invite", object_id: invite_id)
          DB[:workspace_invites].where(id: invite_id).delete
          Broadcaster.object_deleted("workspace_invite", invite_id, workspace_id: workspace_id.to_s)
        end

        APP_LOGGER.info { "[Invites::Cancel] Invite #{invite_id} cancelled in workspace #{workspace_id}" }
        T.cast(
          Success({ deleted: [{ objectType: "workspaceInvite", id: invite_id.to_s }] }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end
    end
  end
end
