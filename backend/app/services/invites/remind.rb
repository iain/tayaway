# frozen_string_literal: true

module Invites
  # Service to resend a workspace invitation, regenerating the token and extending expiry.
  # Rate-limited to once per 24h (counting original creation as first send).
  module Remind
    COOLDOWN_HOURS = 24

    class << self
      include Dry::Monads[:result]

      def call(invite_id:, workspace_id:)
        find_invite(invite_id, workspace_id)
          .bind { |invite| check_not_accepted(invite) }
          .bind { |invite| check_rate_limit(invite) }
          .bind { |invite| resend(invite) }
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

        Success(invite)
      end

      def check_not_accepted(invite)
        if invite.accepted_at
          Failure(ServiceError.validation("This invitation has already been accepted"))
        else
          Success(invite)
        end
      end

      def check_rate_limit(invite)
        last_sent_at = invite.last_reminded_at || invite.created_at
        cooldown_until = last_sent_at + (COOLDOWN_HOURS * 3600)
        if Time.now < cooldown_until
          Failure(ServiceError.validation("A reminder was already sent recently. Please wait before sending another."))
        else
          Success(invite)
        end
      end

      def resend(invite)
        now = Time.now
        raw_token = SecureRandom.hex(32)
        token_hash = Auth::Token.digest(raw_token)
        expires_at = now + (WorkspaceInvite::EXPIRY_HOURS * 3600)

        DB[:workspace_invites].where(id: invite.id).update(
          token: token_hash,
          expires_at: expires_at,
          last_reminded_at: now,
          updated_at: now
        )

        jwt = Auth::Token.encode_invite(token: raw_token, email: invite.email.to_s)
        frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
        invite_link = "#{frontend_url}/invite/accept?token=#{jwt}"

        workspace = Workspace.find(invite.workspace_id)
        workspace_name = workspace ? workspace.name : "Tayaway"

        APP_LOGGER.info { "[Invites::Remind] Reminder sent for invite #{invite.id} to #{invite.email} in workspace #{invite.workspace_id}" }
        APP_LOGGER.info { "REMINDER INVITE LINK FOR #{invite.email}: #{invite_link}" } if APP_ENV == "development"
        Mailers::WorkspaceInvite.send_email(
          email: invite.email,
          invite_link: invite_link,
          workspace_name: workspace_name,
          name: invite.name
        )

        Broadcaster.object_changed("workspace_invite", invite.id, workspace_id: invite.workspace_id.to_s)

        updated_invite = WorkspaceInvite.find(invite.id)
        pool = PoolSerializer.new(workspace_id: invite.workspace_id)
        pool.add_workspace_invite(updated_invite)
        Success({ objects: pool.to_a })
      end
    end
  end
end
