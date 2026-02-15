# typed: false
# frozen_string_literal: true

class App
  hash_branch("api", "users") do |r|
    response.status = 401
    next { error: "Authorization required" } unless current_user

    # /api/users/:id routes
    r.on String do |id|
      r.is do
        # PUT /api/users/:id - Update user name (personal settings)
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
