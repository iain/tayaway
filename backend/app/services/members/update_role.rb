# typed: true
# frozen_string_literal: true

module Members
  # Updates a workspace member's role.
  # Authorization rules:
  #   - owner: can change anyone's role
  #   - admin: can change admin/member roles, but cannot touch owners or promote to owner
  #   - member: cannot change any roles
  module UpdateRole
    class << self
      extend T::Sig
      include Result::Methods

      VALID_ROLES = T.let(["owner", "admin", "member"], T::Array[String])

      sig do
        params(
          acting_user_id: T.any(String, UUID),
          membership_id: String,
          new_role: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(acting_user_id:, membership_id:, new_role:)
        validate_role(new_role)
          .bind { |role| perform(acting_user_id, membership_id, role) }
      end

      private

      sig { params(role: T.nilable(String)).returns(Result[String, ServiceError]) }
      def validate_role(role)
        if role.nil? || !VALID_ROLES.include?(role)
          T.cast(
            Failure(ServiceError.validation("Role must be one of: #{VALID_ROLES.join(", ")}")),
            Result[String, ServiceError]
          )
        else
          T.cast(Success(role), Result[String, ServiceError])
        end
      end

      sig do
        params(
          acting_user_id: T.any(String, UUID),
          membership_id: String,
          new_role: String
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def perform(acting_user_id, membership_id, new_role)
        target = WorkspaceMembership.find(membership_id)
        unless target
          return T.cast(
            Failure(ServiceError.not_found("Member not found")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        acting = WorkspaceMembership.find_by_workspace_and_user(target.workspace_id, acting_user_id)
        unless acting
          return T.cast(
            Failure(ServiceError.forbidden("Access denied")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        if acting.user_id == target.user_id
          return T.cast(
            Failure(ServiceError.forbidden("Cannot change your own role")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        authorized = case acting.role
                     when "owner" then true
                     when "admin" then target.role != "owner" && new_role != "owner"
                     else false
                     end

        unless authorized
          return T.cast(
            Failure(ServiceError.forbidden("Insufficient permissions to change this member's role")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        DB[:workspace_memberships]
          .where(id: target.id.to_s)
          .update(role: new_role, updated_at: Time.now)

        Broadcaster.object_changed("member", target.id.to_s, workspace_id: target.workspace_id.to_s)

        updated = T.must(WorkspaceMembership.find(target.id))
        pool = PoolSerializer.new(workspace_id: target.workspace_id)
        pool.add_member(updated)

        T.cast(
          Success({ objects: pool.to_a }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end
    end
  end
end
