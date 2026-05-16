# frozen_string_literal: true

class WorkspaceSerializer
  class << self
    def serialize_batch(workspaces, pool:)
      return [] if workspaces.empty?

      workspace_ids = workspaces.map { |w| w.id.to_s }
      member_ids_by_workspace = WorkspaceMembership.ids_for_workspaces(workspace_ids)

      workspaces.map do |workspace|
        {
          id: workspace.id.to_s,
          objectType: "workspace",
          name: workspace.name,
          memberIds: member_ids_by_workspace[workspace.id.to_s] || [],
          createdAt: workspace.created_at.iso8601(3),
          updatedAt: workspace.updated_at.iso8601(3)
        }
      end
    end
  end
end
