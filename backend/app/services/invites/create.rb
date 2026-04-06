# frozen_string_literal: true

module Invites
  # Service to create a workspace invitation and send the invite email.
  module Create
    class << self
      include Result::Methods

      def call(email:, workspace_id:, invited_by:, name: nil)
        sanitized_name = name&.strip&.then { |n| n.empty? ? nil : n }
        validate_email(email)
          .bind { |valid_email| validate_name_length(sanitized_name).fmap { valid_email } }
          .bind { |valid_email| check_not_already_member(valid_email, workspace_id) }
          .bind { |valid_email| check_no_pending_invite(valid_email, workspace_id) }
          .bind { |valid_email| create_invite(valid_email, workspace_id, invited_by, sanitized_name) }
      end

      private

      def validate_email(email)
        if email.nil? || email.empty?
          Failure(ServiceError.validation("Email is required"))
        else
          Success(email)
        end
      end

      def validate_name_length(name)
        if name && name.length > ValidationLimits::SHORT_STRING
          Failure(ServiceError.validation("Name is too long (maximum 255 characters)"))
        else
          Success(true)
        end
      end

      def check_not_already_member(email, workspace_id)
        user = User.find_by_email(email)
        if user && WorkspaceMembership.find_by_workspace_and_user(workspace_id, user.id)
          Failure(ServiceError.validation("This user is already a member of this workspace"))
        else
          Success(email)
        end
      end

      def check_no_pending_invite(email, workspace_id)
        if WorkspaceInvite.find_pending(workspace_id, email)
          Failure(ServiceError.validation("An invitation has already been sent to this email"))
        else
          Success(email)
        end
      end

      def create_invite(email, workspace_id, invited_by, name)
        now = Time.now
        id = SecureRandom.uuid
        raw_token = SecureRandom.hex(32)
        token_hash = Auth::Token.digest(raw_token)
        expires_at = now + (WorkspaceInvite::EXPIRY_HOURS * 3600)

        DB[:workspace_invites].insert(
          id: id,
          workspace_id: workspace_id.to_s,
          invited_by: invited_by.to_s,
          email: email,
          name: name,
          token: token_hash,
          expires_at: expires_at,
          created_at: now,
          updated_at: now
        )

        jwt = Auth::Token.encode_invite(token: raw_token, email: email)
        frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
        invite_link = "#{frontend_url}/invite/accept?token=#{jwt}"

        workspace = Workspace.find(workspace_id)
        workspace_name = workspace ? workspace.name : "Tayaway"

        APP_LOGGER.info { "[Invites::Create] Invite #{id} sent to #{email} in workspace #{workspace_id} by #{invited_by}" }
        APP_LOGGER.info { "INVITE LINK FOR #{email}: #{invite_link}" } if APP_ENV == "development"
        Mailers::WorkspaceInvite.send_email(email: email, invite_link: invite_link, workspace_name: workspace_name, name: name)

        Broadcaster.object_changed("workspace_invite", id, workspace_id: workspace_id.to_s)

        invite = WorkspaceInvite.find(id)
        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_workspace_invite(invite)
        Success({ objects: pool.to_a })
      end
    end
  end
end
