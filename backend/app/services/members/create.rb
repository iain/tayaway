# typed: true
# frozen_string_literal: true

module Members
  # Service to add a member to a workspace. Creates user if needed.
  # Accepts an optional client-provided membership UUID for optimistic updates.
  #
  # @example
  #   result = Members::Create.call(
  #     name: "John",
  #     email: "john@example.com",
  #     workspace_id: "uuid",
  #     id: "client-generated-uuid"
  #   )
  #   result.success?  # => true
  #   result.value!    # => { member_id: "uuid", objects: [...] }
  module Create
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          name: T.nilable(String),
          email: T.nilable(String),
          workspace_id: T.nilable(T.any(String, UUID)),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(name:, email:, workspace_id: nil, id: nil)
        validate_email(email)
          .bind { |valid_email| find_or_create_member(name, valid_email, workspace_id, id) }
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
          workspace_id: T.nilable(T.any(String, UUID)),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def find_or_create_member(name, email, workspace_id, id)
        existing_user = User.find_by_email_exact(email)

        if existing_user
          add_existing_user_to_workspace(existing_user, workspace_id, id)
        else
          create_user_and_member(name, email, workspace_id, id)
        end
      end

      sig do
        params(
          user: User,
          workspace_id: T.nilable(T.any(String, UUID)),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def add_existing_user_to_workspace(user, workspace_id, id)
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
        membership_id = id || SecureRandom.uuid

        DB[:workspace_memberships].insert(
          id: membership_id,
          workspace_id: workspace_id.to_s,
          user_id: user.id.to_s,
          role: "member",
          created_at: now
        )

        Broadcaster.object_changed("member", membership_id, workspace_id: workspace_id.to_s)

        membership = WorkspaceMembership.find(membership_id)
        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_member(T.must(membership))

        T.cast(Success({ member_id: membership_id, objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end

      sig do
        params(
          name: T.nilable(String),
          email: String,
          workspace_id: T.nilable(T.any(String, UUID)),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_user_and_member(name, email, workspace_id, id)
        now = Time.now
        user_id = SecureRandom.uuid
        membership_id = id || SecureRandom.uuid

        DB.transaction do
          DB[:users].insert(
            id: user_id,
            email: email,
            name: name&.empty? ? nil : name,
            created_at: now,
            updated_at: now
          )

          # Add user to workspace if provided
          if workspace_id
            DB[:workspace_memberships].insert(
              id: membership_id,
              workspace_id: workspace_id.to_s,
              user_id: user_id,
              role: "member",
              created_at: now
            )

            # Broadcast new member so other clients see new member
            Broadcaster.object_changed("member", membership_id, workspace_id: workspace_id.to_s)
          end
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)

        # Include member in response if workspace was provided
        if workspace_id
          membership = WorkspaceMembership.find(membership_id)
          pool.add_member(T.must(membership))
        end

        T.cast(Success({ member_id: membership_id, objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
