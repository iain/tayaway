# frozen_string_literal: true

module Test
  # Service to create a test session for e2e testing.
  # This service should only be used in test/development environments.
  #
  # @example
  #   result = Test::CreateSession.call(email: "test@example.com", name: "Test User")
  #   result.success?  # => true
  #   result.value!    # => { session_token: "...", user_id: "uuid" }
  module CreateSession
    class << self
      include Result::Methods

      def call(email:, name:)
        validate_email(email).bind { |valid_email| find_or_create_user_and_session(valid_email, name) }
      end

      private

      def validate_email(email)
        if email.nil? || email.empty?
          Failure(ServiceError.validation("Email is required"))
        else
          Success(email)
        end
      end

      def find_or_create_user_and_session(email, name)
        DB.transaction do
          user_id = upsert_user(email, name)
          ensure_default_workspace(user_id)
          session = create_session_for_user(user_id)

          success_data = { session_token: session[:token], user_id: user_id }
          Success(success_data)
        end
      end

      def create_session_for_user(user_id)
        now = Time.now
        id = SecureRandom.uuid
        token = SecureRandom.hex(32)
        expires_at = now + Session::EXPIRY_SECONDS

        DB[:sessions].insert(
          id: id,
          user_id: user_id,
          token: Auth::Token.digest(token),
          expires_at: expires_at,
          created_at: now
        )

        { id: id, token: token, user_id: user_id, expires_at: expires_at, created_at: now }
      end

      def upsert_user(email, name)
        now = Time.now
        id = SecureRandom.uuid
        display_name = name || email

        DB[:users].insert_conflict(
          target: :email,
          update: { name: display_name, updated_at: now }
        ).insert(id: id, email: email, name: display_name, created_at: now, updated_at: now)

        DB[:users].where(email: email).get(:id)
      end

      def ensure_default_workspace(user_id)
        existing = DB[:workspace_memberships].where(user_id: user_id).first
        return if existing

        now = Time.now
        workspace_id = SecureRandom.uuid

        DB[:workspaces].insert(
          id: workspace_id,
          name: "Personal",
          created_at: now,
          updated_at: now
        )

        DB[:workspace_memberships].insert_conflict(
          target: %i[workspace_id user_id]
        ).insert(
          id: SecureRandom.uuid,
          workspace_id: workspace_id,
          user_id: user_id,
          role: "owner",
          created_at: now
        )
      end
    end
  end
end
