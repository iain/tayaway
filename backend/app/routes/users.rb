# typed: false
# frozen_string_literal: true

class App
  hash_branch("api", "users") do |r|
    response.status = 401
    next { error: "Authorization required" } unless current_user

    # GET /api/users - List all users
    r.is do
      r.get do
        users = User.all_ordered
        pool = PoolSerializer.new
        pool.add_all(users, type: :user)

        response.status = 200
        { objects: pool.to_a }
      end

      # POST /api/users - Create a new user in current user's workspace
      r.post do
        # Get current user's first workspace
        first_workspace = Workspace.for_user(current_user.id).first
        workspace_id = first_workspace&.id

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
