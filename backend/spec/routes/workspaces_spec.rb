# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Workspaces endpoints" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
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
end
