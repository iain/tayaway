# typed: false
# frozen_string_literal: true

class App
  hash_branch("api", "workspaces") do |r|
    response.status = 401
    next { error: "Authorization required" } unless current_user

    # GET /api/workspaces - List workspaces for current user
    r.is do
      r.get do
        workspaces = Workspace.for_user(current_user.id)
        pool = PoolSerializer.new
        pool.add_all(workspaces, type: :workspace)

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
      membership = WorkspaceMembership.find_by_workspace_and_user(workspace.id, current_user.id)
      response.status = 403
      next { error: "Access denied" } unless membership

      # GET /api/workspaces/:id - Get workspace details
      r.is do
        r.get do
          pool = PoolSerializer.new(workspace_id: workspace.id)
          pool.add_workspace(workspace)

          response.status = 200
          { objects: pool.to_a }
        end
      end
    end
  end
end
