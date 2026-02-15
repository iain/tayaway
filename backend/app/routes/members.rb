# typed: false
# frozen_string_literal: true

class App
  hash_branch("api", "members") do |r|
    require_auth

    # POST /api/members - Add a member to a workspace (create user if needed)
    r.is do
      r.post do
        workspace_id = r.params["workspace_id"]

        unless workspace_id && member_of_workspace?(workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        result = Members::Create.call(
          name: r.params["name"]&.strip,
          email: r.params["email"]&.strip&.downcase,
          workspace_id: workspace_id,
          id: r.params["id"]
        )
        handle_result(result, success_status: 201)
      end
    end
  end
end
