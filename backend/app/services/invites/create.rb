# typed: true
# frozen_string_literal: true

module Invites
  # Service to create a workspace invitation and send the invite email.
  module Create
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          email: T.nilable(String),
          workspace_id: T.any(String, UUID),
          invited_by: T.any(String, UUID),
          name: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(email:, workspace_id:, invited_by:, name: nil)
        sanitized_name = name&.strip&.then { |n| n.empty? ? nil : n }
        validate_email(email)
          .bind { |valid_email| validate_name_length(sanitized_name).fmap { valid_email } }
          .bind { |valid_email| check_not_already_member(valid_email, workspace_id) }
          .bind { |valid_email| check_no_pending_invite(valid_email, workspace_id) }
          .bind { |valid_email| create_invite(valid_email, workspace_id, invited_by, sanitized_name) }
      end

      private

      sig { params(email: T.nilable(String)).returns(Result[String, ServiceError]) }
      def validate_email(email)
        if email.nil? || email.empty?
          T.cast(Failure(ServiceError.validation("Email is required")), Result[String, ServiceError])
        else
          T.cast(Success(email), Result[String, ServiceError])
        end
      end

      sig { params(name: T.nilable(String)).returns(Result[TrueClass, ServiceError]) }
      def validate_name_length(name)
        if name && name.length > ValidationLimits::SHORT_STRING
          T.cast(Failure(ServiceError.validation("Name is too long (maximum 255 characters)")), Result[TrueClass, ServiceError])
        else
          T.cast(Success(true), Result[TrueClass, ServiceError])
        end
      end

      sig { params(email: String, workspace_id: T.any(String, UUID)).returns(Result[String, ServiceError]) }
      def check_not_already_member(email, workspace_id)
        user = User.find_by_email(email)
        if user && WorkspaceMembership.find_by_workspace_and_user(workspace_id, user.id)
          T.cast(
            Failure(ServiceError.validation("This user is already a member of this workspace")),
            Result[String, ServiceError]
          )
        else
          T.cast(Success(email), Result[String, ServiceError])
        end
      end

      sig { params(email: String, workspace_id: T.any(String, UUID)).returns(Result[String, ServiceError]) }
      def check_no_pending_invite(email, workspace_id)
        if WorkspaceInvite.find_pending(workspace_id, email)
          T.cast(
            Failure(ServiceError.validation("An invitation has already been sent to this email")),
            Result[String, ServiceError]
          )
        else
          T.cast(Success(email), Result[String, ServiceError])
        end
      end

      sig do
        params(
          email: String,
          workspace_id: T.any(String, UUID),
          invited_by: T.any(String, UUID),
          name: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
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

        APP_LOGGER.debug { "INVITE LINK FOR #{email}: #{invite_link}" } if ENV["DEBUG_AUTH_LINKS"]
        Mailers::WorkspaceInvite.send_email(email: email, invite_link: invite_link, workspace_name: workspace_name, name: name)

        Broadcaster.object_changed("workspace_invite", id, workspace_id: workspace_id.to_s)

        invite = T.must(WorkspaceInvite.find(id))
        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_workspace_invite(invite)
        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
