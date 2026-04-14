# frozen_string_literal: true

class WorkspaceInviteSerializer
  class << self
    def serialize_batch(invites, pool:)
      invites.map do |invite|
        {
          id: invite.id.to_s,
          objectType: "workspaceInvite",
          workspaceId: invite.workspace_id.to_s,
          invitedBy: invite.invited_by&.to_s,
          email: invite.email.to_s,
          name: invite.name,
          expiresAt: invite.expires_at.iso8601(3),
          acceptedAt: invite.accepted_at&.iso8601(3),
          lastRemindedAt: invite.last_reminded_at&.iso8601(3),
          createdAt: invite.created_at.iso8601(3),
          updatedAt: invite.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_invite) = {}
    def policy_context_batch(_invites) = {}
  end
end
