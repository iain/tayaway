# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Members::Create do
  it "returns failure when email is missing" do
    result = described_class.call(name: "Test", email: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Email is required")
  end

  it "creates user and member with name and returns success" do
    workspace = TestFactories.workspace

    result = described_class.call(name: "New User", email: "new@example.com", workspace_id: workspace[:id])

    expect(result.success?).to be true
    expect(result.value![:member_id]).to be_a(String)
    expect(result.value![:objects]).to be_an(Array)
    user = DB[:users].where(email: "new@example.com").first
    expect(user[:name]).to eq("New User")
    expect(DB[:users].where(email: "new@example.com").count).to eq(1)
  end

  it "creates user with nil name when name is empty" do
    workspace = TestFactories.workspace

    result = described_class.call(name: "", email: "noname@example.com", workspace_id: workspace[:id])

    expect(result.success?).to be true
    user = DB[:users].where(email: "noname@example.com").first
    expect(user[:name]).to be_nil
  end

  it "accepts a client-provided membership id" do
    workspace = TestFactories.workspace
    client_id = SecureRandom.uuid

    result = described_class.call(name: "Test", email: "clientid@example.com", workspace_id: workspace[:id], id: client_id)

    expect(result.success?).to be true
    expect(result.value![:member_id]).to eq(client_id)
  end

  context "when user already exists" do
    let(:workspace) { TestFactories.workspace }
    let!(:existing_user) { TestFactories.user(email: "existing@example.com") }

    it "adds existing user to workspace instead of creating a new one" do
      result = described_class.call(name: "Ignored", email: "existing@example.com", workspace_id: workspace[:id])

      expect(result.success?).to be true
      expect(DB[:users].where(email: "existing@example.com").count).to eq(1)

      membership = DB[:workspace_memberships].where(
        workspace_id: workspace[:id],
        user_id: existing_user[:id]
      ).first
      expect(membership).not_to be_nil
      expect(membership[:role]).to eq("member")
    end

    it "returns failure when existing user is already a member of the workspace" do
      TestFactories.workspace_membership(workspace: workspace, user: existing_user)

      result = described_class.call(name: "Test", email: "existing@example.com", workspace_id: workspace[:id])

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("This user is already a member of this workspace")
    end

    it "returns failure when existing user and no workspace_id provided" do
      result = described_class.call(name: "Test", email: "existing@example.com")

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("A user with this email already exists")
    end
  end
end
