# typed: true
# frozen_string_literal: true

module Invites
  # Service to accept a workspace invitation.
  # Creates user if needed, creates membership, marks invite accepted, sends magic link.
  module Accept
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(token_jwt: T.nilable(String)).returns(Result[T::Hash[Symbol, String], ServiceError])
      end
      def call(token_jwt:)
        decode_token(token_jwt)
          .bind { |decoded| find_invite(decoded) }
          .bind { |invite| accept_invite(invite) }
      end

      private

      sig { params(token_jwt: T.nilable(String)).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def decode_token(token_jwt)
        if token_jwt.nil? || token_jwt.empty?
          return T.cast(Failure(ServiceError.validation("Token is required")), Result[T::Hash[Symbol, String], ServiceError])
        end

        decoded = Auth::Token.decode_invite(token_jwt)
        T.cast(Success(decoded), Result[T::Hash[Symbol, String], ServiceError])
      rescue JWT::ExpiredSignature
        T.cast(Failure(ServiceError.gone("This invitation has expired")), Result[T::Hash[Symbol, String], ServiceError])
      rescue JWT::DecodeError
        T.cast(Failure(ServiceError.validation("Invalid invitation link")), Result[T::Hash[Symbol, String], ServiceError])
      end

      sig { params(decoded: T::Hash[Symbol, String]).returns(Result[WorkspaceInvite, ServiceError]) }
      def find_invite(decoded)
        token_hash = Auth::Token.digest(T.must(decoded[:token]))
        invite = WorkspaceInvite.find_valid(token_hash, T.must(decoded[:email]))

        if invite
          T.cast(Success(invite), Result[WorkspaceInvite, ServiceError])
        else
          T.cast(Failure(ServiceError.gone("This invitation is no longer valid")), Result[WorkspaceInvite, ServiceError])
        end
      end

      sig { params(invite: WorkspaceInvite).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def accept_invite(invite)
        now = Time.now
        user = T.let(nil, T.nilable(User))
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
            user = T.must(User.find(user_id))
          end

          # Check not already a member (race condition guard)
          existing = WorkspaceMembership.find_by_workspace_and_user(invite.workspace_id, user.id)
          if existing
            # Mark invite accepted but skip membership creation
            DB[:workspace_invites].where(id: invite.id).update(accepted_at: now, updated_at: now)
            DB[:deleted_items].insert(workspace_id: invite.workspace_id, object_type: "workspace_invite", object_id: invite.id)
            Broadcaster.object_deleted("workspace_invite", invite.id, workspace_id: invite.workspace_id.to_s)
            return T.cast(
              Success({ message: "You are already a member of this workspace" }),
              Result[T::Hash[Symbol, String], ServiceError]
            )
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

        user = T.must(user)

        APP_LOGGER.info { "[Invites::Accept] User #{user.id} (#{user.email}) accepted invite to workspace #{invite.workspace_id}" }

        # Broadcast new member
        Broadcaster.object_changed("member", membership_id, workspace_id: invite.workspace_id.to_s)

        # Send magic link so the user can sign in
        send_magic_link(user)

        T.cast(
          Success({ message: "Invitation accepted. Check your email for a sign-in link." }),
          Result[T::Hash[Symbol, String], ServiceError]
        )
      end

      sig { params(user: User).void }
      def send_magic_link(user)
        DB[:magic_link_tokens].where(user_id: user.id.to_s, used_at: nil).update(used_at: Time.now)

        raw_token = SecureRandom.hex(32)
        now = Time.now
        expires_at = now + (MagicLinkToken::EXPIRY_MINUTES * 60)

        DB[:magic_link_tokens].insert(
          id: SecureRandom.uuid,
          user_id: user.id,
          token: Auth::Token.digest(raw_token),
          email: user.email.to_s,
          expires_at: expires_at,
          created_at: now
        )

        jwt = Auth::Token.encode_magic_link(token: raw_token, email: user.email.to_s)
        frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
        magic_link = "#{frontend_url}/auth/verify?token=#{jwt}"

        workspaces = Workspace.for_user(user.id)
        workspace_name = workspaces.length == 1 ? T.must(workspaces.first).name : "Tayaway"

        APP_LOGGER.debug { "MAGIC LINK FOR #{user.email}: #{magic_link}" } if ENV["DEBUG_AUTH_LINKS"]
        Mailers::MagicLink.send_email(email: user.email, magic_link: magic_link, workspace_name: workspace_name)
      end
    end
  end
end
