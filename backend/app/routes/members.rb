# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

class App
  hash_branch("api", "members") do |r|
    require_auth

    # PUT /api/members/:id - Update member role
    r.on String do |id|
      r.put do
        target = WorkspaceMembership.find(id)
        unless target
          response.status = 404
          next { error: "Member not found" }
        end

        unless member_of_workspace?(target.workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        result = Members::UpdateRole.call(
          membership: current_membership,
          membership_id: id,
          new_role: r.params["role"]
        )
        handle_result(result)
      end
    end
  end
end
