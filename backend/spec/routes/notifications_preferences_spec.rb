# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Notification preferences endpoints" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }
  let(:json_headers) { auth_headers.merge("CONTENT_TYPE" => "application/json") }

  describe "GET /api/notifications/preferences" do
    it "returns 401 without auth" do
      get "/api/notifications/preferences"

      expect(last_response.status).to eq(401)
    end

    it "lists every kind with default channel state" do
      get "/api/notifications/preferences", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      keys = body["kinds"].map { |k| k["key"] }
      expect(keys).to include("workspace_invite", "poll_closed", "settlement_created")
      poll_closed = body["kinds"].find { |k| k["key"] == "poll_closed" }
      email = poll_closed["channels"].find { |c| c["channel"] == "email" }
      expect(email).to include("enabled" => true)
    end

    it "reflects the user's stored override" do
      DB[:user_notification_preferences].insert(
        user_id: user[:id], kind: "poll_closed", channel: "email", enabled: false
      )

      get "/api/notifications/preferences", {}, auth_cookie

      body = JSON.parse(last_response.body)
      poll_closed = body["kinds"].find { |k| k["key"] == "poll_closed" }
      expect(poll_closed["channels"].first["enabled"]).to be false
    end
  end

  describe "PUT /api/notifications/preferences" do
    it "stores an override" do
      put "/api/notifications/preferences",
          { kind: "poll_closed", channel: "email", enabled: false }.to_json,
          json_headers

      expect(last_response.status).to eq(200)
      row = DB[:user_notification_preferences]
            .where(user_id: user[:id], kind: "poll_closed", channel: "email").first
      expect(row[:enabled]).to be false
    end

    it "rejects an unknown kind" do
      put "/api/notifications/preferences",
          { kind: "no_such", channel: "email", enabled: true }.to_json,
          json_headers

      expect(last_response.status).to eq(400)
    end
  end

  describe "POST /api/notifications/preferences/silence" do
    it "returns 401 without auth" do
      post "/api/notifications/preferences/silence",
           { kind: "expense_added" }.to_json,
           "CONTENT_TYPE" => "application/json"

      expect(last_response.status).to eq(401)
    end

    it "silences every configurable channel for the kind" do
      post "/api/notifications/preferences/silence",
           { kind: "expense_added" }.to_json,
           json_headers

      expect(last_response.status).to eq(200)
      rows = DB[:user_notification_preferences]
             .where(user_id: user[:id], kind: "expense_added")
             .all
      channels = rows.map { |r| r[:channel] }.sort
      expect(channels).to eq(%w[email in_app push])
      expect(rows.map { |r| r[:enabled] }.uniq).to eq([false])
    end

    it "rejects an unknown kind" do
      post "/api/notifications/preferences/silence",
           { kind: "no_such" }.to_json,
           json_headers

      expect(last_response.status).to eq(400)
    end
  end
end
