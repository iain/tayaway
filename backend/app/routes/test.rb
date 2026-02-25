# typed: false
# frozen_string_literal: true

# Test-only endpoints for e2e tests.
# These endpoints should NOT be enabled in production.
class App
  hash_branch("api", "test") do |r|
    unless %w[test development e2e].include?(ENV["RACK_ENV"])
      response.status = 404
      next { error: "Not found" }
    end

    # POST /api/test/session - Create an authenticated session
    r.is "session" do
      r.post do
        result = Test::CreateSession.call(
          email: r.params["email"]&.strip&.downcase,
          name: r.params["name"]&.strip
        )
        if result.success?
          set_session_cookie(result.value![:session_token], Time.now + (Session::EXPIRY_DAYS * 24 * 60 * 60))
        end
        handle_result(result)
      end
    end

    # POST /api/test/add-member - Directly add a user to a workspace (bypasses invite flow)
    r.is "add-member" do
      r.post do
        email = r.params["email"]&.strip&.downcase
        workspace_id = r.params["workspace_id"]

        user = User.find_by_email(email)
        unless user
          response.status = 404
          next { error: "User not found" }
        end

        existing = WorkspaceMembership.find_by_workspace_and_user(workspace_id, user.id)
        if existing
          response.status = 200
          next { member_id: existing.id.to_s }
        end

        now = Time.now
        membership_id = SecureRandom.uuid
        DB[:workspace_memberships].insert(
          id: membership_id,
          workspace_id: workspace_id,
          user_id: user.id.to_s,
          role: "member",
          created_at: now
        )
        Broadcaster.object_changed("member", membership_id, workspace_id: workspace_id)

        response.status = 201
        { member_id: membership_id }
      end
    end

    # POST /api/test/reset - Truncate all tables
    r.is "reset" do
      r.post do
        DB.run("TRUNCATE votes, date_ranges, date_polls, events, sessions, magic_link_tokens, workspace_invites, workspace_memberships, workspaces, users CASCADE")

        response.status = 200
        { message: "Database reset" }
      end
    end
  end
end
