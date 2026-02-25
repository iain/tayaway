# typed: false
# frozen_string_literal: true

class App
  hash_branch("api", "members") do |r|
    require_auth

    # PUT /api/members/:id - Update member role
    r.on String do |id|
      r.put do
        result = Members::UpdateRole.call(
          acting_user_id: current_user.id,
          membership_id: id,
          new_role: r.params["role"]
        )
        handle_result(result)
      end
    end
  end
end
