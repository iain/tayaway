# frozen_string_literal: true

module Invites
  # Service to accept a workspace invitation.
  # Creates user if needed, creates membership, marks invite accepted, sends login link.
  module Accept
    class << self
      def call(token_jwt:)
        # Not audited: the actor isn't known until the JWT decodes, and this
        # is really an authentication concern. Picked up when auth gets its
        # own audit pass.
        Success()
          .bind { decode_token(token_jwt) }
          .bind { |decoded| find_invite(decoded) }
          .bind { |invite| accept_invite(invite) }
      end

      private

      def decode_token(token_jwt)
        if token_jwt.nil? || token_jwt.empty?
          return Failure(ServiceError.validation("Token is required"))
        end

        decoded = Auth::Token.decode_invite(token_jwt)
        Success(decoded)
      rescue JWT::ExpiredSignature
        Failure(ServiceError.gone("This invitation has expired"))
      rescue JWT::DecodeError
        Failure(ServiceError.validation("Invalid invitation link"))
      end

      def find_invite(decoded)
        token_hash = Auth::Token.digest(decoded[:token])
        invite = WorkspaceInvite.find_valid(token_hash, decoded[:email])

        if invite
          Success(invite)
        else
          Failure(ServiceError.gone("This invitation is no longer valid"))
        end
      end

      def accept_invite(invite)
        now = Time.now
        user = nil
        membership_id = SecureRandom.uuid

        DB.transaction do
          # Find or create user
          user = User.find_by_email(invite.email.to_s)
          unless user
            user_id = SecureRandom.uuid
            DB[:users].insert(
              id: user_id,
              email: invite.email.to_s,
              name: invite.name,
              created_at: now,
              updated_at: now
            )
            user = User.find(user_id)
          end

          # Check not already a member (race condition guard)
          existing = WorkspaceMembership.find_by_workspace_and_user(invite.workspace_id, user.id)
          if existing
            # Mark invite accepted but skip membership creation
            DB[:workspace_invites].where(id: invite.id).update(accepted_at: now, updated_at: now)
            DB[:deleted_items].insert(workspace_id: invite.workspace_id, object_type: "workspace_invite", object_id: invite.id)
            Broadcaster.object_deleted("workspace_invite", invite.id, workspace_id: invite.workspace_id.to_s)
            return Success({ message: "You are already a member of this workspace" })
          end

          # Create membership
          DB[:workspace_memberships].insert(
            id: membership_id,
            workspace_id: invite.workspace_id.to_s,
            user_id: user.id.to_s,
            role: "member",
            created_at: now
          )

          # Mark invite accepted and remove from pool
          DB[:workspace_invites].where(id: invite.id).update(accepted_at: now, updated_at: now)
          DB[:deleted_items].insert(workspace_id: invite.workspace_id, object_type: "workspace_invite", object_id: invite.id)
          Broadcaster.object_deleted("workspace_invite", invite.id, workspace_id: invite.workspace_id.to_s)
        end

        APP_LOGGER.info { "[Invites::Accept] User #{user.id} (#{user.email}) accepted invite to workspace #{invite.workspace_id}" }

        # Broadcast new member
        Broadcaster.object_changed("member", membership_id, workspace_id: invite.workspace_id.to_s)

        # Send login link so the user can log in
        Auth::CreateLoginLink.send_login_link(user)

        Success({ message: "Invitation accepted. Check your email for a login link." })
      end
    end
  end
end
