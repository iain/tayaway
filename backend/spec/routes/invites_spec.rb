# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Invites endpoints" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }
  let(:workspace) { TestFactories.workspace }

  define_method(:create_workspace_invite) do |workspace:, email: "invitee@example.com", expires_at: nil|
    expires_at ||= Time.now + 3600
    now = Time.now
    invite_id = SecureRandom.uuid
    raw_token = SecureRandom.hex(32)
    token_hash = Auth::Token.digest(raw_token)
    DB[:workspace_invites].insert(
      id: invite_id,
      workspace_id: workspace[:id],
      invited_by: user[:id],
      email: email,
      token: token_hash,
      expires_at: expires_at,
      created_at: now,
      updated_at: now
    )
    { id: invite_id, raw_token: raw_token, email: email }
  end

  describe "GET /api/invites/info" do
    it "returns 400 when token is missing" do
      get "/api/invites/info"

      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("Token is required")
    end

    it "returns 400 for an invalid token" do
      get "/api/invites/info?token=not-a-valid-jwt"

      expect(last_response.status).to eq(400)
      body = JSON.parse(last_response.body)
      expect(body["error"]).to eq("Invalid invitation link")
    end

    it "returns workspace name and email for a valid token" do
      TestFactories.workspace_membership(workspace: workspace, user: user, role: "admin")
      invite = create_workspace_invite(workspace: workspace)
      jwt = Auth::Token.encode_invite(token: invite[:raw_token], email: invite[:email])

      get "/api/invites/info?token=#{jwt}"

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      expect(body["workspaceName"]).to eq(workspace[:name])
      expect(body["email"]).to eq(invite[:email])
    end

    it "returns 410 for an invite that is no longer valid" do
      # Create an invite whose DB record has already expired
      invite = create_workspace_invite(workspace: workspace, expires_at: Time.now - 3600)
      jwt = Auth::Token.encode_invite(token: invite[:raw_token], email: invite[:email])

      get "/api/invites/info?token=#{jwt}"

      expect(last_response.status).to eq(410)
    end
  end

  describe "POST /api/invites/accept" do
    it "returns 400 when token is missing or invalid" do
      post "/api/invites/accept",
           { token: "bad-token" }.to_json,
           { "CONTENT_TYPE" => "application/json" }.merge(csrf_header)

      expect(last_response.status).to eq(400)
    end

    it "accepts an invitation and creates a user + membership" do
      invite = create_workspace_invite(workspace: workspace, email: "newperson@example.com")
      jwt = Auth::Token.encode_invite(token: invite[:raw_token], email: invite[:email])

      post "/api/invites/accept",
           { token: jwt }.to_json,
           { "CONTENT_TYPE" => "application/json" }.merge(csrf_header)

      expect(last_response.status).to eq(200)
      # User should have been created
      created_user = DB[:users].where(email: "newperson@example.com").first
      expect(created_user).not_to be_nil
      # Membership should have been created
      membership = DB[:workspace_memberships].where(
        workspace_id: workspace[:id],
        user_id: created_user[:id]
      ).first
      expect(membership).not_to be_nil
    end
  end

  describe "GET /api/invites" do
    it "returns 401 without auth" do
      get "/api/invites"

      expect(last_response.status).to eq(401)
    end

    it "returns 403 when not a member of the workspace" do
      other_workspace = TestFactories.workspace

      get "/api/invites?workspace_id=#{other_workspace[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(403)
    end

    it "returns pending invites for the workspace" do
      TestFactories.workspace_membership(workspace: workspace, user: user, role: "admin")
      create_workspace_invite(workspace: workspace, email: "pending@example.com")

      get "/api/invites?workspace_id=#{workspace[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      invite = body["objects"].find { |o| o["objectType"] == "workspaceInvite" }
      expect(invite).not_to be_nil
      expect(invite["email"]).to eq("pending@example.com")
    end
  end

  describe "POST /api/invites" do
    it "returns 401 without auth" do
      post "/api/invites"

      expect(last_response.status).to eq(401)
    end

    it "returns 403 when not a member of the workspace" do
      other_workspace = TestFactories.workspace

      post "/api/invites",
           { workspace_id: other_workspace[:id], email: "someone@example.com" }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end

    it "returns 403 when user is only a member (not admin/owner)" do
      TestFactories.workspace_membership(workspace: workspace, user: user, role: "member")

      post "/api/invites",
           { workspace_id: workspace[:id], email: "someone@example.com" }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end

    it "creates an invitation when user is admin" do
      TestFactories.workspace_membership(workspace: workspace, user: user, role: "admin")

      post "/api/invites",
           { workspace_id: workspace[:id], email: "newmember@example.com" }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      invite = body["objects"].find { |o| o["objectType"] == "workspaceInvite" }
      expect(invite["email"]).to eq("newmember@example.com")
    end
  end

  describe "DELETE /api/invites/:id" do
    it "returns 401 without auth" do
      delete "/api/invites/#{SecureRandom.uuid}"

      expect(last_response.status).to eq(401)
    end

    it "cancels an invitation when user is admin" do
      TestFactories.workspace_membership(workspace: workspace, user: user, role: "admin")
      invite = create_workspace_invite(workspace: workspace)

      delete "/api/invites/#{invite[:id]}?workspace_id=#{workspace[:id]}", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:workspace_invites].where(id: invite[:id]).count).to eq(0)
    end

    it "returns 403 when user is only a member" do
      TestFactories.workspace_membership(workspace: workspace, user: user, role: "member")
      invite = create_workspace_invite(workspace: workspace)

      delete "/api/invites/#{invite[:id]}?workspace_id=#{workspace[:id]}", {}, auth_headers

      expect(last_response.status).to eq(403)
    end
  end

  describe "POST /api/invites/:id/remind" do
    it "returns 401 without auth" do
      post "/api/invites/#{SecureRandom.uuid}/remind"

      expect(last_response.status).to eq(401)
    end

    it "resends an invitation when user is admin" do
      TestFactories.workspace_membership(workspace: workspace, user: user, role: "admin")
      # Create with created_at in the past so rate limit cooldown is passed
      invite = create_workspace_invite(workspace: workspace, expires_at: Time.now + (25 * 3600))
      DB[:workspace_invites].where(id: invite[:id]).update(created_at: Time.now - (25 * 3600))

      post "/api/invites/#{invite[:id]}/remind?workspace_id=#{workspace[:id]}",
           {}.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
    end

    it "returns 403 when user is only a member" do
      TestFactories.workspace_membership(workspace: workspace, user: user, role: "member")
      invite = create_workspace_invite(workspace: workspace)

      post "/api/invites/#{invite[:id]}/remind?workspace_id=#{workspace[:id]}",
           {}.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end
  end
end
