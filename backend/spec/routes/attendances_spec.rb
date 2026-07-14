# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attendance and guest endpoints" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header, "CONTENT_TYPE" => "application/json") }
  let(:workspace) { TestFactories.workspace }
  let(:event) { TestFactories.event(workspace: workspace, user: user) }

  before do
    TestFactories.workspace_membership(workspace: workspace, user: user)
    DB[:events].where(id: event[:id]).update(start_date: Date.today, end_date: Date.today + 7)
  end

  describe "GET /api/events/:id/attendances" do
    it "returns the event's attendances with permissions" do
      guest = TestFactories.guest(workspace: workspace)
      TestFactories.attendance(event: event, user: user)
      TestFactories.attendance(event: event, guest: guest, host: user)

      get "/api/events/#{event[:id]}/attendances", {}, auth_cookie

      expect(last_response.status).to eq(200)
      objects = JSON.parse(last_response.body)["objects"]
      attendances = objects.select { |o| o["objectType"] == "attendance" }
      expect(attendances.length).to eq(2)
      expect(attendances.first["permissions"]).to include("edit", "decline")
    end

    it "returns 403 for non-members" do
      outsider = TestFactories.user
      outsider_session = TestFactories.session(user: outsider)

      get "/api/events/#{event[:id]}/attendances", {}, { "HTTP_COOKIE" => "session_token=#{outsider_session[:token]}" }

      expect(last_response.status).to eq(403)
    end
  end

  describe "POST /api/events/:id/attendances" do
    it "defaults the subject to the actor and returns the pooled attendance" do
      post "/api/events/#{event[:id]}/attendances",
           { id: SecureRandom.uuid, status: "going" }.to_json,
           auth_headers

      expect(last_response.status).to eq(201)
      attendance = JSON.parse(last_response.body)["objects"].find { |o| o["objectType"] == "attendance" }
      expect(attendance["userId"]).to eq(user[:id])
      expect(attendance["status"]).to eq("going")
    end

    it "creates guest and attendance from an inline payload and pools both" do
      post "/api/events/#{event[:id]}/attendances",
           { id: SecureRandom.uuid, status: "going", guest: { id: SecureRandom.uuid, name: "Emma" } }.to_json,
           auth_headers

      expect(last_response.status).to eq(201)
      objects = JSON.parse(last_response.body)["objects"]
      attendance = objects.find { |o| o["objectType"] == "attendance" }
      guest = objects.find { |o| o["objectType"] == "guest" }
      expect(guest["name"]).to eq("Emma")
      expect(attendance["guestId"]).to eq(guest["id"])
      expect(attendance["hostUserId"]).to eq(user[:id])
    end

    it "translates service failures to their http status" do
      post "/api/events/#{event[:id]}/attendances",
           { id: SecureRandom.uuid, status: "maybe" }.to_json,
           auth_headers

      expect(last_response.status).to eq(400)
    end
  end

  describe "guests endpoints" do
    it "lists, creates, renames, and deletes workspace guests" do
      post "/api/workspaces/#{workspace[:id]}/guests", { id: SecureRandom.uuid, name: "Emma" }.to_json, auth_headers
      expect(last_response.status).to eq(201)
      guest_id = JSON.parse(last_response.body)["objects"].first["id"]

      get "/api/workspaces/#{workspace[:id]}/guests", {}, auth_cookie
      names = JSON.parse(last_response.body)["objects"].map { |o| o["name"] }
      expect(names).to eq(["Emma"])

      put "/api/workspaces/#{workspace[:id]}/guests/#{guest_id}", { name: "Emma Jones" }.to_json, auth_headers
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["objects"].first["name"]).to eq("Emma Jones")

      delete "/api/workspaces/#{workspace[:id]}/guests/#{guest_id}", {}, auth_headers
      expect(last_response.status).to eq(200)
      expect(JSON.parse(last_response.body)["deleted"]).to eq([{ "objectType" => "guest", "id" => guest_id }])
    end

    it "returns 403 when deleting a referenced guest" do
      guest = TestFactories.guest(workspace: workspace)
      TestFactories.attendance(event: event, guest: guest, host: user, status: "declined")

      delete "/api/workspaces/#{workspace[:id]}/guests/#{guest[:id]}", {}, auth_headers

      expect(last_response.status).to eq(403)
    end
  end
end
