# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkspaceInvite do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  # rubocop:disable Sorbet/BlockMethodDefinition -- test helper used across examples
  def create_invite(email: "invite@example.com", workspace_id: workspace[:id], invited_by: user[:id], expires_at: Time.now + 3600, accepted_at: nil)
    now = Time.now
    id = SecureRandom.uuid
    DB[:workspace_invites].insert(
      id: id,
      workspace_id: workspace_id,
      invited_by: invited_by,
      email: email,
      token: Auth::Token.digest("token-#{id}"),
      expires_at: expires_at,
      accepted_at: accepted_at,
      created_at: now,
      updated_at: now
    )
    described_class.find(id)
  end
  # rubocop:enable Sorbet/BlockMethodDefinition

  describe ".find" do
    it "returns an invite by id" do
      invite = create_invite
      found = described_class.find(invite.id)

      expect(found).not_to be_nil
      expect(found.email.to_s).to eq("invite@example.com")
    end

    it "returns nil for unknown id" do
      expect(described_class.find(SecureRandom.uuid)).to be_nil
    end
  end

  describe ".find_valid" do
    it "returns a valid invite matching token hash and email" do
      raw_token = "test-token-123"
      token_hash = Auth::Token.digest(raw_token)
      now = Time.now
      id = SecureRandom.uuid
      DB[:workspace_invites].insert(
        id: id,
        workspace_id: workspace[:id],
        invited_by: user[:id],
        email: "valid@example.com",
        token: token_hash,
        expires_at: now + 3600,
        created_at: now,
        updated_at: now
      )

      found = described_class.find_valid(token_hash, "valid@example.com")
      expect(found).not_to be_nil
      expect(found.id.to_s).to eq(id)
    end

    it "returns nil for expired invite" do
      raw_token = "expired-token"
      token_hash = Auth::Token.digest(raw_token)
      now = Time.now
      DB[:workspace_invites].insert(
        id: SecureRandom.uuid,
        workspace_id: workspace[:id],
        invited_by: user[:id],
        email: "expired@example.com",
        token: token_hash,
        expires_at: now - 1,
        created_at: now,
        updated_at: now
      )

      expect(described_class.find_valid(token_hash, "expired@example.com")).to be_nil
    end

    it "returns nil for accepted invite" do
      raw_token = "accepted-token"
      token_hash = Auth::Token.digest(raw_token)
      now = Time.now
      DB[:workspace_invites].insert(
        id: SecureRandom.uuid,
        workspace_id: workspace[:id],
        invited_by: user[:id],
        email: "accepted@example.com",
        token: token_hash,
        expires_at: now + 3600,
        accepted_at: now,
        created_at: now,
        updated_at: now
      )

      expect(described_class.find_valid(token_hash, "accepted@example.com")).to be_nil
    end

    it "returns nil for wrong email" do
      raw_token = "wrong-email-token"
      token_hash = Auth::Token.digest(raw_token)
      now = Time.now
      DB[:workspace_invites].insert(
        id: SecureRandom.uuid,
        workspace_id: workspace[:id],
        invited_by: user[:id],
        email: "real@example.com",
        token: token_hash,
        expires_at: now + 3600,
        created_at: now,
        updated_at: now
      )

      expect(described_class.find_valid(token_hash, "wrong@example.com")).to be_nil
    end
  end

  describe ".find_pending" do
    it "returns a pending invite for workspace and email" do
      invite = create_invite(email: "pending@example.com")
      found = described_class.find_pending(workspace[:id], "pending@example.com")

      expect(found).not_to be_nil
      expect(found.id.to_s).to eq(invite.id.to_s)
    end

    it "returns nil for accepted invite" do
      create_invite(email: "done@example.com", accepted_at: Time.now)
      expect(described_class.find_pending(workspace[:id], "done@example.com")).to be_nil
    end
  end

  describe ".pending_for_workspace" do
    it "returns only pending, non-expired invites" do
      create_invite(email: "a@example.com")
      create_invite(email: "b@example.com")
      create_invite(email: "expired@example.com", expires_at: Time.now - 1)
      create_invite(email: "accepted@example.com", accepted_at: Time.now)

      invites = described_class.pending_for_workspace(workspace[:id])
      emails = invites.map { |i| i.email.to_s }

      expect(emails).to contain_exactly("a@example.com", "b@example.com")
    end
  end

  describe "#to_api_hash" do
    it "serializes the invite" do
      invite = create_invite
      hash = invite.to_api_hash

      expect(hash[:id]).to eq(invite.id.to_s)
      expect(hash[:workspaceId]).to eq(workspace[:id])
      expect(hash[:email]).to eq("invite@example.com")
      expect(hash).to have_key(:expiresAt)
      expect(hash).to have_key(:createdAt)
    end
  end
end
