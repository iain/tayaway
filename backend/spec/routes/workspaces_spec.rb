# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Workspaces endpoints" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }
  let(:workspace) { TestFactories.workspace }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe "GET /api/workspaces" do
    it "returns 401 without auth" do
      get "/api/workspaces"

      expect(last_response.status).to eq(401)
    end

    it "returns the user's workspaces" do
      get "/api/workspaces", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      ws = body["objects"].find { |o| o["objectType"] == "workspace" && o["id"] == workspace[:id] }
      expect(ws).not_to be_nil
      expect(ws["name"]).to eq(workspace[:name])
    end

    it "does not return workspaces the user does not belong to" do
      other_workspace = TestFactories.workspace

      get "/api/workspaces", {}, auth_cookie

      body = JSON.parse(last_response.body)
      ids = body["objects"].select { |o| o["objectType"] == "workspace" }.map { |o| o["id"] }
      expect(ids).not_to include(other_workspace[:id])
    end
  end

  describe "POST /api/workspaces" do
    it "returns 401 without auth" do
      post "/api/workspaces", { "name" => "Beta" }, csrf_header

      expect(last_response.status).to eq(401)
    end

    it "creates a workspace owned by the caller and returns it pool-shaped" do
      post "/api/workspaces", { "name" => "Beta", "timezone" => "Europe/Lisbon" }, auth_headers

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      ws = body["objects"].find { |o| o["objectType"] == "workspace" }
      expect(ws["name"]).to eq("Beta")
      expect(ws["timezone"]).to eq("Europe/Lisbon")
      # The membership rides along so the client can tell straight away that
      # it owns the new workspace, without waiting for the sync.
      member = body["objects"].find { |o| o["objectType"] == "member" && o["workspaceId"] == ws["id"] }
      expect(member["role"]).to eq("owner")
      expect(member["userId"]).to eq(user[:id])
    end

    it "rejects an invalid name" do
      post "/api/workspaces", { "name" => " " }, auth_headers

      expect(last_response.status).to eq(400)
    end
  end

  describe "PATCH /api/workspaces/:id" do
    let(:admin) { TestFactories.user }
    let(:admin_session) { TestFactories.session(user: admin) }
    let(:admin_headers) { { "HTTP_COOKIE" => "session_token=#{admin_session[:token]}" }.merge(csrf_header) }

    before { TestFactories.workspace_membership(workspace: workspace, user: admin, role: "admin") }

    it "renames the workspace for an admin" do
      patch "/api/workspaces/#{workspace[:id]}", { "name" => "Renamed" }, admin_headers

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      ws = body["objects"].find { |o| o["objectType"] == "workspace" }
      expect(ws["name"]).to eq("Renamed")
    end

    it "returns 403 for a plain member" do
      patch "/api/workspaces/#{workspace[:id]}", { "name" => "Renamed" }, auth_headers

      expect(last_response.status).to eq(403)
      expect(DB[:workspaces].where(id: workspace[:id]).get(:name)).to eq(workspace[:name])
    end

    it "returns 403 when not a member at all" do
      other_workspace = TestFactories.workspace

      patch "/api/workspaces/#{other_workspace[:id]}", { "name" => "Renamed" }, auth_headers

      expect(last_response.status).to eq(403)
    end
  end

  describe "GET /api/workspaces/:id" do
    it "returns 401 without auth" do
      get "/api/workspaces/#{workspace[:id]}"

      expect(last_response.status).to eq(401)
    end

    it "returns 404 for non-existent workspace" do
      get "/api/workspaces/#{SecureRandom.uuid}", {}, auth_cookie

      expect(last_response.status).to eq(404)
    end

    it "returns 403 when not a member of the workspace" do
      other_workspace = TestFactories.workspace

      get "/api/workspaces/#{other_workspace[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(403)
    end

    it "returns workspace details" do
      get "/api/workspaces/#{workspace[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      ws = body["objects"].find { |o| o["objectType"] == "workspace" }
      expect(ws["name"]).to eq(workspace[:name])
    end
  end

  describe "GET /api/workspaces/:id/audit-log" do
    let(:owner_user) { TestFactories.user(name: "Olive Owner") }
    let(:owner_session) { TestFactories.session(user: owner_user) }
    let(:owner_cookie) { { "HTTP_COOKIE" => "session_token=#{owner_session[:token]}" } }

    before { TestFactories.workspace_membership(workspace: workspace, user: owner_user, role: "owner") }

    it "returns 401 without auth" do
      get "/api/workspaces/#{workspace[:id]}/audit-log"

      expect(last_response.status).to eq(401)
    end

    it "returns 403 for non-owner members" do
      get "/api/workspaces/#{workspace[:id]}/audit-log", {}, auth_cookie

      expect(last_response.status).to eq(403)
    end

    it "returns entries for the owner" do
      TestFactories.audit_log_entry(workspace: workspace, actor_user: owner_user, service: "Events::Create")

      get "/api/workspaces/#{workspace[:id]}/audit-log", {}, owner_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["entries"].length).to eq(1)
      expect(body["entries"].first).to include(
        "service" => "Events::Create",
        "actorName" => "Olive Owner",
        "outcome" => "success"
      )
      expect(body["nextCursor"]).to be_nil
    end

    it "pages through entries via the cursor param" do
      101.times { |i| TestFactories.audit_log_entry(workspace: workspace, service: "Svc::N#{i}", created_at: Time.now - i) }

      get "/api/workspaces/#{workspace[:id]}/audit-log", {}, owner_cookie

      body = JSON.parse(last_response.body)
      expect(body["entries"].length).to eq(100)
      expect(body["nextCursor"]).to be_a(String)

      get "/api/workspaces/#{workspace[:id]}/audit-log", { "cursor" => body["nextCursor"] }, owner_cookie

      second = JSON.parse(last_response.body)
      expect(second["entries"].length).to eq(1)
      expect(second["entries"].first["service"]).to eq("Svc::N100")
      expect(second["nextCursor"]).to be_nil
    end

    it "rejects a malformed cursor" do
      get "/api/workspaces/#{workspace[:id]}/audit-log", { "cursor" => "garbage" }, owner_cookie

      expect(last_response.status).to eq(400)
    end
  end
end
