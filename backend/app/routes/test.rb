# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

# Test-only endpoints for e2e tests.
# These endpoints should NOT be enabled in production.
class App
  hash_branch("api", "test") do |r|
    unless Config.local?
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
          set_session_cookie(result.value![:session_token], Time.now + Session::EXPIRY_SECONDS)
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

        now = Time.now
        membership_id = SecureRandom.uuid
        inserted = DB[:workspace_memberships]
                   .returning(:id)
                   .insert_conflict(target: %i[workspace_id user_id])
                   .insert(
                     id: membership_id,
                     workspace_id: workspace_id,
                     user_id: user.id.to_s,
                     role: "member",
                     created_at: now
                   )
                   .first

        if inserted
          Broadcaster.object_changed("member", membership_id, workspace_id: workspace_id)
          response.status = 201
          next { member_id: membership_id }
        end

        existing = WorkspaceMembership.find_by_workspace_and_user(workspace_id, user.id)
        response.status = 200
        { member_id: existing.id.to_s }
      end
    end

    # POST /api/test/reset - Truncate all tables
    r.is "reset" do
      r.post do
        DB.run("TRUNCATE votes, date_ranges, date_polls, events, sessions, login_link_tokens, workspace_invites, workspace_memberships, workspaces, users CASCADE")

        response.status = 200
        { message: "Database reset" }
      end
    end

    # POST /api/test/dispatch-test-push - Fire one synthetic push delivery
    # to the current user's stored subscriptions. Used by the push smoke
    # test to drive a real round-trip from web-push to a fake push service
    # the test stands up locally. Bypasses the job queue (which only runs
    # under falcon-host, not `falcon serve` as the e2e backend does) and
    # signs/sends inline.
    r.is "dispatch-test-push" do
      r.post do
        user = current_user
        unless user
          response.status = 401
          next { error: "Not authenticated" }
        end

        payload = JSON.generate(
          title: "Smoke Test",
          body: "Hello from the e2e push smoke test",
          href: "/"
        )

        begin
          PushSubscription.for_user(user.id).each do |sub|
            Notifications::Channels::Push.deliver_now(
              endpoint: sub.endpoint,
              p256dh_key: sub.p256dh_key,
              auth_key: sub.auth_key,
              payload: payload
            )
          end
          { ok: true }
        rescue StandardError => e
          response.status = 500
          { error: "#{e.class}: #{e.message}", backtrace: e.backtrace&.first(5) }
        end
      end
    end
  end
end
