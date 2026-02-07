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
        user = User.find_by_email(email)
        user_id = if user
                    if name && user.name != name
                      DB[:users].where(id: user.id).update(name: name, updated_at: Time.now)
                    end
                    user.id
                  else
                    now = Time.now
                    id = SecureRandom.uuid
                    DB[:users].insert(id: id, email: email, name: name, created_at: now, updated_at: now)
                    id
                  end

        # Ensure user has at least one workspace
        ensure_default_workspace(user_id)

        session = create_session_for_user(user_id)

        T.cast(Success({
          session_token: session[:token],
          user_id: user_id
        }
                      ), Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
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
          token: token,
          expires_at: expires_at,
          created_at: now
        )

        T.must(DB[:sessions].where(id: id).first)
      end

      sig { params(user_id: T.any(String, UUID)).void }
      def ensure_default_workspace(user_id)
        # Check if user already has a workspace
        existing = DB[:workspace_memberships].where(user_id: user_id).first
        return if existing

        # Create a default workspace for the user
        now = Time.now
        workspace_id = SecureRandom.uuid

        DB[:workspaces].insert(
          id: workspace_id,
          name: "Personal",
          created_at: now,
          updated_at: now
        )

        DB[:workspace_memberships].insert(
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
