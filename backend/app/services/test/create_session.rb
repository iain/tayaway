# typed: true
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
      extend T::Sig
      include Result::Methods

      sig do
        params(email: T.nilable(String), name: T.nilable(String))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(email:, name:)
        validate_email(email).bind { |valid_email| find_or_create_user_and_session(valid_email, name) }
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

      sig do
        params(email: String, name: T.nilable(String))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def find_or_create_user_and_session(email, name)
        DB.transaction do
          user_id = upsert_user(email, name)
          ensure_default_workspace(user_id)
          session = create_session_for_user(user_id)

          success_data = { session_token: session[:token], user_id: user_id }
          T.cast(Success(success_data), Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
      end

      sig { params(user_id: T.any(String, UUID)).returns(T::Hash[Symbol, T.untyped]) }
      def create_session_for_user(user_id)
        now = Time.now
        id = SecureRandom.uuid
        token = SecureRandom.hex(32)
        expires_at = now + (Session::EXPIRY_DAYS * 24 * 60 * 60)

        DB[:sessions].insert(
          id: id,
          user_id: user_id,
          token: Auth::Token.digest(token),
          expires_at: expires_at,
          created_at: now
        )

        { id: id, token: token, user_id: user_id, expires_at: expires_at, created_at: now }
      end

      sig { params(email: String, name: T.nilable(String)).returns(String) }
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

      sig { params(user_id: T.any(String, UUID)).void }
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
