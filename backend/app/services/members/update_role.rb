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

        Broadcaster.object_changed("member", target.id.to_s, workspace_id: target.workspace_id.to_s)

        notify_target(target, old_role, new_role) if old_role != new_role && acting_membership.user_id.to_s != target.user_id.to_s

        updated = WorkspaceMembership.find(target.id)
        pool = PoolSerializer.new(membership: acting_membership)
        pool.add(:member, [updated])

        Success({ objects: pool.to_a })
      end

      def notify_target(target, old_role, new_role)
        Notifications::Safely.deliver(context: "Members::UpdateRole") do
          user = User.find(target.user_id)
          workspace = Workspace.find(target.workspace_id)
          return unless user && workspace

          Notifications::Dispatch.call(
            kind: :member_role_changed,
            user_id: target.user_id.to_s,
            workspace_id: target.workspace_id.to_s,
            data: {
              email: user.email.to_s,
              recipient_name: user.name,
              workspace_name: workspace.name,
              old_role: old_role,
              new_role: new_role,
              workspace_url: ENV.fetch("FRONTEND_URL", "https://tayaway.nl").to_s
            }
          )
        end
      end
    end
  end
end
