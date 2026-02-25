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
        ).returns(Result[T::Hash[Symbol, String], ServiceError])
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

      sig { params(invite: WorkspaceInvite).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def delete_invite(invite)
        DB[:workspace_invites].where(id: invite.id).delete
        T.cast(Success({ message: "Invitation cancelled" }), Result[T::Hash[Symbol, String], ServiceError])
      end
    end
  end
end
