# frozen_string_literal: true

module Guests
  # Standalone guest creation (workspace-scoped). The usual path for a *new*
  # guest is the inline payload on Attendances::Upsert — one command, one
  # transaction; this exists for the backfill converter and for managing
  # guests outside an event context. Idempotent on the client-generated id:
  # a replay never overwrites the stored name (renames go through
  # Guests::Rename).
  module Create
    class << self
      include LengthValidation

      def call(workspace_id:, membership:, name:, guest_id:, placeholder: false)
        resolved_id = guest_id.nil? || guest_id.empty? ? SecureRandom.uuid : guest_id

        Auditable.around(
          service: "Guests::Create",
          actor: membership,
          subject_type: "guest",
          subject_id: resolved_id,
          context: { placeholder: placeholder }
        ) do
          Success()
            .bind { find_workspace(workspace_id) }
            .bind { |workspace| WorkspacePolicy.enforce(:create_guest, workspace, membership: membership) }
            .bind { |workspace| validate_id_collision(workspace, resolved_id) }
            .bind { |workspace| validate_length(name, max: ValidationLimits::SHORT_STRING, field: "Name", required: true).bind { Success(workspace) } }
            .bind { |workspace| create_guest(workspace, name.strip, resolved_id, membership.user_id, placeholder) }
        end
      end

      private

      def find_workspace(workspace_id)
        workspace = Workspace.find(workspace_id)
        if workspace
          Success(workspace)
        else
          Failure(ServiceError.not_found("Workspace not found"))
        end
      end

      # An existing row under this id in another workspace must not be
      # silently claimed as ours by the DO NOTHING conflict below.
      def validate_id_collision(workspace, id)
        existing = Guest.find(id)
        if existing && existing.workspace_id.to_s != workspace.id.to_s
          Failure(ServiceError.validation("Guest is not part of this workspace"))
        else
          Success(workspace)
        end
      end

      def create_guest(workspace, name, id, actor_user_id, placeholder)
        row = nil
        DB.transaction do
          now = Time.now
          row = DB[:guests]
                .returning(:id)
                .insert_conflict(target: :id)
                .insert(
                  id: id,
                  workspace_id: workspace.id,
                  name: name,
                  placeholder: placeholder,
                  created_by_user_id: actor_user_id,
                  created_at: now,
                  updated_at: now
                )
                .first
          Broadcaster.object_changed("guest", id) if row
        end

        Success({ guest_id: id, created: !row.nil? })
      end
    end
  end
end
