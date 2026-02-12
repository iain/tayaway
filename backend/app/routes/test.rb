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
        handle_result(result)
      end
    end

    # POST /api/test/reset - Truncate all tables
    r.is "reset" do
      r.post do
        DB.run("TRUNCATE votes, date_ranges, date_polls, events, sessions, magic_link_tokens, workspace_memberships, workspaces, users CASCADE")

        response.status = 200
        { message: "Database reset" }
      end
    end
  end
end
