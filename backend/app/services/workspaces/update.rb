# frozen_string_literal: true

module Workspaces
  # Renames a workspace and/or changes its default timezone.
  #
  # PATCH semantics: a nil field means "leave it alone", so the settings form
  # can save one section without blanking the rest.
  module Update
    class << self
      include Workspaces::Validators

      def call(workspace_id:, membership:, name: nil, timezone: nil)
        Auditable.around(
          service: "Workspaces::Update",
          actor: membership,
          subject_type: "workspace",
          subject_id: workspace_id,
          context: { name: name, timezone: timezone }
        ) do
          Success()
            .bind { Workspace.find_result(workspace_id) }
            .bind { |workspace| WorkspacePolicy.enforce(:edit, workspace, membership: membership) }
            .bind { |workspace| validate_name(name, required: !name.nil?).fmap { workspace } }
            .bind { |workspace| validate_timezone(timezone).fmap { workspace } }
            .bind { |workspace| apply(workspace, name: name, timezone: timezone) }
        end
      end

      private

      def apply(workspace, name:, timezone:)
        changes = {}
        changes[:name] = name.strip unless name.nil?
        changes[:timezone] = timezone unless timezone.nil? || timezone.empty?

        unless changes.empty?
          changes[:updated_at] = Time.now
          DB[:workspaces].where(id: workspace.id).update(changes)
          Broadcaster.object_changed("workspace", workspace.id)
        end

        Success({ workspace_id: workspace.id.to_s })
      end
    end
  end
end
