# frozen_string_literal: true

module Members
  # Updates a workspace member's role.
  # Authorization rules:
  #   - owner: can change anyone's role
  #   - admin: can change admin/member roles, but cannot touch owners or promote to owner
  #   - member: cannot change any roles
  module UpdateRole
    class << self
      include Result::Methods

      VALID_ROLES = ["owner", "admin", "member"]

      def call(acting_user_id:, membership_id:, new_role:)
        validate_role(new_role)
          .bind { |role| perform(acting_user_id, membership_id, role) }
      end

      private

      def validate_role(role)
        if role.nil? || !VALID_ROLES.include?(role)
          Failure(ServiceError.validation("Role must be one of: #{VALID_ROLES.join(", ")}"))
        else
          Success(role)
        end
      end

      def perform(acting_user_id, membership_id, new_role)
        target = WorkspaceMembership.find(membership_id)
        unless target
          return Failure(ServiceError.not_found("Member not found"))
        end

        acting = WorkspaceMembership.find_by_workspace_and_user(target.workspace_id, acting_user_id)
        unless acting
          return Failure(ServiceError.forbidden("Access denied"))
        end

        if acting.user_id == target.user_id
          return Failure(ServiceError.forbidden("Cannot change your own role"))
        end

        authorized = case acting.role
                     when "owner" then true
                     when "admin" then target.role != "owner" && new_role != "owner"
                     else false
                     end

        unless authorized
          return Failure(ServiceError.forbidden("Insufficient permissions to change this member's role"))
        end

        APP_LOGGER.info { "[Members::UpdateRole] User #{acting_user_id} changed member #{target.id} role from #{target.role} to #{new_role} in workspace #{target.workspace_id}" }
        DB[:workspace_memberships]
          .where(id: target.id.to_s)
          .update(role: new_role, updated_at: Time.now)

        Broadcaster.object_changed("member", target.id.to_s, workspace_id: target.workspace_id.to_s)

        updated = WorkspaceMembership.find(target.id)
        pool = PoolSerializer.new(workspace_id: target.workspace_id)
        pool.add_member(updated)

        Success({ objects: pool.to_a })
      end
    end
  end
end
