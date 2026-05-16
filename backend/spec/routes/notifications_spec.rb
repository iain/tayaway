# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Notifications inbox endpoints" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }

  def insert_notification(user_id: user[:id], kind: "poll_closed", read_at: nil, data: { title: "T", body: "B" }, created_at: nil)
    id = SecureRandom.uuid
    row = {
      id: id,
      user_id: user_id,
      kind: kind,
      data: Sequel.pg_jsonb(data),
      read_at: read_at
    }
    row[:created_at] = created_at if created_at
    DB[:notifications].insert(row)
    id
  end

  describe "GET /api/notifications" do
    it "returns 401 without auth" do
      get "/api/notifications"

      expect(last_response.status).to eq(401)
    end

    it "returns notifications as pool objects, newest first" do
      old_id = insert_notification(data: { title: "old" }, created_at: Time.now - 60)
      new_id = insert_notification(data: { title: "new" }, created_at: Time.now)

      get "/api/notifications", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["objects"].map { |n| n["objectType"] }).to all(eq("notification"))
      expect(body["objects"].map { |n| n["id"] }).to eq([new_id, old_id])
    end

    it "doesn't leak another user's notifications" do
      other = TestFactories.user
      insert_notification(user_id: other[:id])

      get "/api/notifications", {}, auth_cookie

      body = JSON.parse(last_response.body)
      expect(body["objects"]).to be_empty
    end
  end

  describe "PUT /api/notifications/:id/read" do
    it "marks one notification read" do
      id = insert_notification

      put "/api/notifications/#{id}/read", "{}", auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      expect(DB[:notifications].where(id: id).get(:read_at)).not_to be_nil
    end

    it "broadcasts the change so other devices update" do
      id = insert_notification
      allow(Broadcaster).to receive(:object_changed)

      put "/api/notifications/#{id}/read", "{}", auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(Broadcaster).to have_received(:object_changed).with("notification", id)
    end

    it "doesn't broadcast when the row was already read" do
      id = insert_notification(read_at: Time.now - 60)
      allow(Broadcaster).to receive(:object_changed)

      put "/api/notifications/#{id}/read", "{}", auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(Broadcaster).not_to have_received(:object_changed)
    end

    it "doesn't mark another user's notification" do
      other = TestFactories.user
      id = insert_notification(user_id: other[:id])

      put "/api/notifications/#{id}/read", "{}", auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(DB[:notifications].where(id: id).get(:read_at)).to be_nil
    end

    it "doesn't broadcast when targeting another user's notification" do
      other = TestFactories.user
      id = insert_notification(user_id: other[:id])
      allow(Broadcaster).to receive(:object_changed)

      put "/api/notifications/#{id}/read", "{}", auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(Broadcaster).not_to have_received(:object_changed)
    end
  end

  describe "GET /api/notifications/push-config" do
    it "returns the configured VAPID public key" do
      APP_CONFIG.with(vapid_public_key: "test-public-key") do
        get "/api/notifications/push-config", {}, auth_cookie

        expect(last_response.status).to eq(200)
        body = JSON.parse(last_response.body)
        expect(body["vapidPublicKey"]).to eq("test-public-key")
      end
    end

    it "returns an empty key when VAPID isn't configured" do
      APP_CONFIG.with(vapid_public_key: nil) do
        get "/api/notifications/push-config", {}, auth_cookie

        expect(last_response.status).to eq(200)
        expect(JSON.parse(last_response.body)["vapidPublicKey"]).to eq("")
      end
    end
  end

  describe "POST /api/notifications/push-subscriptions" do
    let(:subscription_body) do
      {
        endpoint: "https://push.example.com/abc",
        p256dhKey: "p256dh-test",
        authKey: "auth-test"
      }.to_json
    end

    it "stores a subscription" do
      post "/api/notifications/push-subscriptions",
           subscription_body,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      row = DB[:push_subscriptions].where(user_id: user[:id]).first
      expect(row[:endpoint]).to eq("https://push.example.com/abc")
    end

    it "rejects an empty endpoint" do
      post "/api/notifications/push-subscriptions",
           { endpoint: "" }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(400)
    end
  end

  describe "PUT /api/notifications/read-all" do
    it "marks every unread notification read" do
      insert_notification
      insert_notification
      already_read = insert_notification(read_at: Time.now - 60)
      original_read_at = DB[:notifications].where(id: already_read).get(:read_at)

      put "/api/notifications/read-all", "{}", auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      expect(DB[:notifications].where(user_id: user[:id], read_at: nil).count).to eq(0)
      # Pre-existing read_at must not have been clobbered.
      expect(DB[:notifications].where(id: already_read).get(:read_at)).to eq(original_read_at)
    end

    it "broadcasts each newly-read row so other devices update" do
      a = insert_notification
      b = insert_notification
      insert_notification(read_at: Time.now - 60)
      allow(Broadcaster).to receive(:object_changed)

      put "/api/notifications/read-all", "{}", auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(Broadcaster).to have_received(:object_changed).with("notification", a)
      expect(Broadcaster).to have_received(:object_changed).with("notification", b)
      expect(Broadcaster).to have_received(:object_changed).twice
    end

    it "doesn't broadcast when there's nothing to mark" do
      insert_notification(read_at: Time.now - 60)
      allow(Broadcaster).to receive(:object_changed)

      put "/api/notifications/read-all", "{}", auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(Broadcaster).not_to have_received(:object_changed)
    end
  end
end
