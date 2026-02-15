# typed: true
# frozen_string_literal: true

module Users
  # Service to update a user's name.
  #
  # @example
  #   result = Users::UpdateName.call(
  #     user_id: "uuid",
  #     current_user_id: "uuid",
  #     name: "New Name"
  #   )
  #   result.success?  # => true
  #   result.value!    # => { objects: [...] }
  module UpdateName
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          user_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          name: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(user_id:, current_user_id:, name:)
        find_user(user_id)
          .bind { |user| authorize(user, current_user_id) }
          .bind { |user| validate_name(name, user) }
          .bind { |user| update_name(user, name) }
      end

      private

      sig { params(user_id: T.any(String, UUID)).returns(Result[User, ServiceError]) }
      def find_user(user_id)
        user = User.find(user_id)
        if user
          T.cast(Success(user), Result[User, ServiceError])
        else
          T.cast(Failure(ServiceError.not_found("User not found")), Result[User, ServiceError])
        end
      end

      sig { params(user: User, current_user_id: T.any(String, UUID)).returns(Result[User, ServiceError]) }
      def authorize(user, current_user_id)
        if user.id == current_user_id
          T.cast(Success(user), Result[User, ServiceError])
        else
          T.cast(Failure(ServiceError.forbidden("Access denied")), Result[User, ServiceError])
        end
      end

      sig { params(name: T.nilable(String), user: User).returns(Result[User, ServiceError]) }
      def validate_name(name, user)
        if name.nil? || name.strip.empty?
          T.cast(Failure(ServiceError.validation("Name is required")), Result[User, ServiceError])
        else
          T.cast(Success(user), Result[User, ServiceError])
        end
      end

      sig do
        params(user: User, name: T.nilable(String)).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_name(user, name)
        user_id = user.id

        DB.transaction do
          DB[:users].where(id: user_id.to_s).update(
            name: T.must(name).strip,
            updated_at: Time.now
          )

          # Broadcast member changes to all workspaces the user belongs to
          WorkspaceMembership.for_user(user_id).each do |m|
            Broadcaster.object_changed("member", m.id, workspace_id: m.workspace_id)
          end
        end

        # Build pool with member objects for each workspace membership
        memberships = WorkspaceMembership.for_user(user_id)

        # Use the first workspace for pool context (members from all workspaces will be added)
        pool = PoolSerializer.new
        memberships.each do |m|
          pool.add_member_from_membership(m)
        end

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
