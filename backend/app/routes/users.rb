# typed: false
# frozen_string_literal: true

class App
  hash_branch("api", "users") do |r|
    user = require_auth

    # /api/users/:id routes
    r.on String do |id|
      r.is do
        # PUT /api/users/:id - Update user name (personal settings)
        r.put do
          result = Users::UpdateName.call(
            user_id: id,
            current_user_id: user.id,
            name: r.params["name"]&.strip
          )
          handle_result(result)
        end
      end
    end
  end
end
