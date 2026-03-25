# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Members endpoints" do
  let(:owner) { TestFactories.user }
  let(:session) { TestFactories.session(user: owner) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }
  let(:workspace) { TestFactories.workspace }

  before { TestFactories.workspace_membership(workspace: workspace, user: owner, role: "owner") }

  describe "PUT /api/members/:id" do
    it "returns 401 without auth" do
      put "/api/members/#{SecureRandom.uuid}"

      expect(last_response.status).to eq(401)
    end

    it "returns 404 for non-existent membership" do
      put "/api/members/#{SecureRandom.uuid}",
          { role: "admin" }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(404)
    end

    it "allows an owner to change a member's role to admin" do
      target_user = TestFactories.user
      membership = TestFactories.workspace_membership(workspace: workspace, user: target_user, role: "member")

      put "/api/members/#{membership[:id]}",
          { role: "admin" }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      updated = body["objects"].find { |o| o["objectType"] == "member" }
      expect(updated["role"]).to eq("admin")
    end

    it "returns 403 when an admin tries to change an owner's role" do
      admin_user = TestFactories.user
      admin_session = TestFactories.session(user: admin_user)
      admin_auth = { "HTTP_COOKIE" => "session_token=#{admin_session[:token]}" }.merge(csrf_header)
      TestFactories.workspace_membership(workspace: workspace, user: admin_user, role: "admin")

      # owner membership
      owner_membership = DB[:workspace_memberships]
                         .where(workspace_id: workspace[:id], user_id: owner[:id])
                         .first

      put "/api/members/#{owner_membership[:id]}",
          { role: "member" }.to_json,
          admin_auth.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end

    it "returns 403 when a plain member tries to change roles" do
      member_user = TestFactories.user
      member_session = TestFactories.session(user: member_user)
      member_auth = { "HTTP_COOKIE" => "session_token=#{member_session[:token]}" }.merge(csrf_header)
      TestFactories.workspace_membership(workspace: workspace, user: member_user, role: "member")

      target_user = TestFactories.user
      target_membership = TestFactories.workspace_membership(workspace: workspace, user: target_user, role: "member")

      put "/api/members/#{target_membership[:id]}",
          { role: "admin" }.to_json,
          member_auth.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end
  end
end
