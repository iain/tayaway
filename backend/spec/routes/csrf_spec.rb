# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "CSRF protection" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }

  describe "mutating requests require X-CSRF-Protection header" do
    it "returns 403 on POST without CSRF header" do
      post "/api/events", { name: "Test" }.to_json,
           auth_cookie.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
      expect(JSON.parse(last_response.body)).to eq("error" => "Forbidden")
    end

    it "returns 403 on PUT without CSRF header" do
      put "/api/users/#{user[:id]}",
          { name: "New Name" }.to_json,
          auth_cookie.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
      expect(JSON.parse(last_response.body)).to eq("error" => "Forbidden")
    end

    it "returns 403 on DELETE without CSRF header" do
      workspace = TestFactories.workspace
      TestFactories.workspace_membership(workspace: workspace, user: user)
      list = TestFactories.task_list(workspace: workspace, user: user)

      delete "/api/task-lists/#{list[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(403)
      expect(JSON.parse(last_response.body)).to eq("error" => "Forbidden")
    end

    it "allows POST with CSRF header" do
      workspace = TestFactories.workspace
      TestFactories.workspace_membership(workspace: workspace, user: user)

      post "/api/task-lists",
           { workspace_id: workspace[:id], name: "My List" }.to_json,
           auth_cookie.merge(csrf_header).merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
    end

    it "allows DELETE with CSRF header" do
      workspace = TestFactories.workspace
      TestFactories.workspace_membership(workspace: workspace, user: user)
      list = TestFactories.task_list(workspace: workspace, user: user)

      delete "/api/task-lists/#{list[:id]}", {}, auth_cookie.merge(csrf_header)

      expect(last_response.status).to eq(200)
    end
  end

  describe "GET requests do not require CSRF header" do
    it "allows GET without CSRF header" do
      workspace = TestFactories.workspace
      TestFactories.workspace_membership(workspace: workspace, user: user)

      get "/api/task-lists?workspace_id=#{workspace[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(200)
    end
  end

  describe "unauthenticated mutation endpoints are not affected" do
    it "allows POST /api/auth/magic-link without CSRF header" do
      post "/api/auth/magic-link",
           { email: "test@example.com" }.to_json,
           { "CONTENT_TYPE" => "application/json" }

      # Any non-403 status confirms CSRF check is not applied here
      expect(last_response.status).not_to eq(403)
    end
  end

  describe "require_session endpoints also enforce CSRF" do
    it "returns 403 on POST /api/auth/logout without CSRF header" do
      post "/api/auth/logout", {}, auth_cookie.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
      expect(JSON.parse(last_response.body)).to eq("error" => "Forbidden")
    end

    it "allows POST /api/auth/logout with CSRF header" do
      post "/api/auth/logout", {},
           auth_cookie.merge(csrf_header).merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
    end
  end
end
