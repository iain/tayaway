# typed: true
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

      # POST /api/users - Create a new user
      r.post do
        result = Users::Create.call(
          name: r.params["name"]&.strip,
          email: r.params["email"]&.strip&.downcase
        )
        handle_result(result, success_status: 201)
      end
    end
  end
end
