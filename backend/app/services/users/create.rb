# typed: true
# frozen_string_literal: true

module Users
  # Service to create a new user and add them to a workspace.
  # If the user already exists (by email), adds them to the workspace instead.
  #
  # @example
  #   result = Users::Create.call(
  #     name: "John",
  #     email: "john@example.com",
  #     workspace_id: "uuid"
  #   )
  #   result.success?  # => true
  #   result.value!    # => { user_id: "uuid", objects: [...] }
  module Create
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          name: T.nilable(String),
          email: T.nilable(String),
          workspace_id: T.nilable(T.any(String, UUID))
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(name:, email:, workspace_id: nil)
        validate_email(email)
          .bind { |valid_email| find_or_create_user(name, valid_email, workspace_id) }
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
        params(
          name: T.nilable(String),
          email: String,
          workspace_id: T.nilable(T.any(String, UUID))
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def find_or_create_user(name, email, workspace_id)
        existing_user = User.find_by_email_exact(email)

        if existing_user
          add_existing_user_to_workspace(existing_user, workspace_id)
        else
          create_user(name, email, workspace_id)
        end
      end

      sig do
        params(
          user: User,
          workspace_id: T.nilable(T.any(String, UUID))
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def add_existing_user_to_workspace(user, workspace_id)
        unless workspace_id
          return T.cast(
            Failure(ServiceError.validation("A user with this email already exists")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        # Check if already a member
        if WorkspaceMembership.find_by_workspace_and_user(workspace_id, user.id)
          return T.cast(
            Failure(ServiceError.validation("This user is already a member of this workspace")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        now = Time.now
        membership_id = SecureRandom.uuid

        DB[:workspace_memberships].insert(
          id: membership_id,
          workspace_id: workspace_id.to_s,
          user_id: user.id.to_s,
          role: "member",
          created_at: now
        )

        Broadcaster.object_changed("workspace_membership", membership_id, workspace_id: workspace_id.to_s)

        pool = PoolSerializer.new
        pool.add_user(user)
        membership = WorkspaceMembership.find_by_workspace_and_user(workspace_id, user.id)
        pool.add_workspace_membership(membership) if membership

        T.cast(Success({ user_id: user.id.to_s, objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end

      sig do
        params(
          name: T.nilable(String),
          email: String,
          workspace_id: T.nilable(T.any(String, UUID))
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_user(name, email, workspace_id)
        now = Time.now
        id = SecureRandom.uuid

        DB.transaction do
          DB[:users].insert(
            id: id,
            email: email,
            name: name&.empty? ? nil : name,
            created_at: now,
            updated_at: now
          )

          # Add user to workspace if provided
          if workspace_id
            membership_id = SecureRandom.uuid
            DB[:workspace_memberships].insert(
              id: membership_id,
              workspace_id: workspace_id.to_s,
              user_id: id,
              role: "member",
              created_at: now
            )

            # Broadcast new membership so other clients see new member
            Broadcaster.object_changed("workspace_membership", membership_id, workspace_id: workspace_id.to_s)
          end
        end

        user = T.must(User.find(id))
        pool = PoolSerializer.new
        pool.add_user(user)

        # Include workspace membership in response if created
        if workspace_id
          membership = WorkspaceMembership.find_by_workspace_and_user(workspace_id, id)
          pool.add_workspace_membership(membership) if membership
        end

        T.cast(Success({ user_id: id, objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
