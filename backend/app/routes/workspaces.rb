# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

class App
  hash_branch("api", "workspaces") do |r|
    user = require_auth

    # GET /api/workspaces - List workspaces for current user
    r.is do
      r.get do
        workspaces = Workspace.for_user(user.id)
        pool = PoolSerializer.new
        pool.add(:workspace, workspaces)

        response.status = 200
        { objects: pool.to_a }
      end
    end

    # /api/workspaces/:id routes
    r.on String do |id|
      workspace = Workspace.find(id)

      response.status = 404
      next { error: "Workspace not found" } unless workspace

      # Check user is a member of the workspace
      membership = WorkspaceMembership.find_by_workspace_and_user(workspace.id, user.id)
      response.status = 403
      next { error: "Access denied" } unless membership

      # GET /api/workspaces/:id - Get workspace details
      r.is do
        r.get do
          pool = PoolSerializer.new(membership: membership)
          pool.add(:workspace, [workspace])

          response.status = 200
          { objects: pool.to_a }
        end
      end

      # GET /api/workspaces/:id/audit-log - Owner-only audit trail page.
      # Deliberately not pool-shaped: audit rows never sync to clients.
      r.get "audit-log" do
        result = AuditLogs::ListForWorkspace.call(
          workspace_id: workspace.id,
          membership: membership,
          cursor: r.params["cursor"]
        )
        handle_result(result)
      end
    end
  end
end
