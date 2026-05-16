# frozen_string_literal: true

module Members
  # Updates a workspace member's role.
  # Authorization rules:
  #   - owner: can change anyone's role
  #   - admin: can change admin/member roles, but cannot touch owners or promote to owner
  #   - member: cannot change any roles
  module UpdateRole
    class << self
      VALID_ROLES = ["owner", "admin", "member"]

      def call(acting_membership:, membership_id:, new_role:)
        Auditable.around(
          service: "Members::UpdateRole",
          actor: acting_membership,
          subject_type: "workspace_membership",
          subject_id: membership_id,
          context: { new_role: new_role }
        ) do
          Success()
            .bind { validate_role(new_role) }
            .bind { |role| find_target(membership_id).fmap { |target| [target, role] } }
            .bind { |(target, role)| MemberPolicy.enforce(:change_role, target, membership: acting_membership).fmap { |_| [target, role] } }
            .bind { |(target, role)| perform(acting_membership, target, role) }
        end
      end

      private

      def validate_role(role)
        if role.nil? || !VALID_ROLES.include?(role)
          Failure(ServiceError.validation("Role must be one of: #{VALID_ROLES.join(", ")}"))
        else
          Success(role)
        end
      end

      def find_target(membership_id)
        target = WorkspaceMembership.find(membership_id)
        if target
          Success(target)
        else
          Failure(ServiceError.not_found("Member not found"))
        end
      end

      def perform(acting_membership, target, new_role)
        old_role = target.role
        APP_LOGGER.info { "[Members::UpdateRole] User #{acting_membership.user_id} changed member #{target.id} role from #{old_role} to #{new_role} in workspace #{target.workspace_id}" }
        DB[:workspace_memberships]
          .where(id: target.id.to_s)
          .update(role: new_role, updated_at: Time.now)

        # One NOTIFY — the Listener fans out to workspace + user audiences
        # via ObjectRegistry so the affected user's other sessions see the
        # role change even when they're looking at a different workspace.
        Broadcaster.object_changed("member", target.id.to_s)

        if old_role != new_role && acting_membership.user_id.to_s != target.user_id.to_s
          Members::OnRoleChanged.call(member: target, old_role: old_role, new_role: new_role)
        end

        updated = WorkspaceMembership.find(target.id)
        pool = PoolSerializer.new(membership: acting_membership)
        pool.add(:member, [updated])

        Success({ objects: pool.to_a })
      end
    end
  end
end
