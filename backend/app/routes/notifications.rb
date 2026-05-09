# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

class App
  hash_branch("api", "notifications") do |r|
    user = require_auth

    r.on "preferences" do
      r.is do
        # GET /api/notifications/preferences - effective preferences for the current user
        r.get do
          result = Notifications::Preferences::Fetch.call(user_id: user.id)
          handle_result(result)
        end

        # PUT /api/notifications/preferences - upsert one (kind, channel) override
        r.put do
          result = Notifications::Preferences::Update.call(
            user_id: user.id,
            kind: r.params["kind"],
            channel: r.params["channel"],
            enabled: r.params["enabled"] == true
          )
          handle_result(result)
        end
      end
    end

    r.on "read-all" do
      # PUT /api/notifications/read-all - mark every unread notification read
      r.put do
        Notification.mark_all_read(user.id)
        { ok: true }
      end
    end

    r.on "push-subscriptions" do
      r.is do
        # POST /api/notifications/push-subscriptions - register a browser push subscription
        r.post do
          endpoint = r.params["endpoint"].to_s
          if endpoint.empty?
            response.status = 400
            { error: "endpoint is required" }
          else
            PushSubscription.upsert(
              user_id: user.id,
              endpoint: endpoint,
              p256dh_key: r.params["p256dhKey"].to_s,
              auth_key: r.params["authKey"].to_s,
              user_agent: r.env["HTTP_USER_AGENT"]
            )
            { ok: true, vapidPublicKey: ENV.fetch("VAPID_PUBLIC_KEY", "") }
          end
        end

        # DELETE /api/notifications/push-subscriptions - unregister
        r.delete do
          PushSubscription.delete_by_endpoint(user_id: user.id, endpoint: r.params["endpoint"].to_s)
          { ok: true }
        end
      end
    end

    r.on "push-config" do
      r.is do
        # GET /api/notifications/push-config - VAPID public key for the browser
        r.get do
          { vapidPublicKey: ENV["VAPID_PUBLIC_KEY"].to_s }
        end
      end
    end

    r.is do
      # GET /api/notifications - the current user's recent notifications
      r.get do
        notifications = Notification.for_user(user.id)
        {
          notifications: notifications.map(&:to_api_hash),
          unreadCount: Notification.unread_count_for_user(user.id)
        }
      end
    end

    # Notification id matcher — kept last so literal-segment routes
    # above always win. `r.on String` matches any single segment, so
    # putting it earlier would swallow `push-subscriptions`,
    # `push-config`, etc. and 404 from the inner block.
    r.on String do |id|
      r.on "read" do
        # PUT /api/notifications/:id/read - mark one notification read
        r.put do
          Notification.mark_read(id, user_id: user.id)
          { ok: true }
        end
      end
    end
  end
end
