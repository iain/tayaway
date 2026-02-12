# typed: false
# frozen_string_literal: true

class App
  hash_branch("api", "users") do |r|
    response.status = 401
    next { error: "Authorization required" } unless current_user

    # GET /api/users - List users in the current user's workspaces
    r.is do
      r.get do
        workspaces = Workspace.for_user(current_user.id)
        pool = PoolSerializer.new
        workspaces.each { |w| pool.add_workspace(w) }

        response.status = 200
        { objects: pool.to_a }
      end

      # POST /api/users - Create a new user (or add existing) in the specified workspace
      r.post do
        workspace_id = r.params["workspace_id"]

        unless workspace_id && member_of_workspace?(workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        result = Users::Create.call(
          name: r.params["name"]&.strip,
          email: r.params["email"]&.strip&.downcase,
          workspace_id: workspace_id
        )
        handle_result(result, success_status: 201)
      end
    end

    # /api/users/:id routes
    r.on String do |id|
      r.is do
        # PUT /api/users/:id - Update user name
        r.put do
          result = Users::UpdateName.call(
            user_id: id,
            current_user_id: current_user.id,
            name: r.params["name"]&.strip
          )
          handle_result(result)
        end
      end
    end
  end
end
