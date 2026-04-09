# frozen_string_literal: true

require "spec_helper"

RSpec.describe Invites::Create do
  let(:workspace) { TestFactories.workspace(name: "Test Workspace") }
  let(:user) { TestFactories.user }
  let(:membership_row) { TestFactories.workspace_membership(workspace: workspace, user: user, role: "admin") }
  let(:membership) { WorkspaceMembership.find(membership_row[:id]) }

  it "creates an invite and sends email" do
    result = described_class.call(
      email: "new@example.com",
      workspace_id: workspace[:id],
      membership: membership
    )

    expect(result.success?).to be true
    objects = result.value![:objects]
    invite_obj = objects.find { |o| o[:objectType] == "workspaceInvite" }
    expect(invite_obj[:email]).to eq("new@example.com")
    expect(invite_obj[:workspaceId]).to eq(workspace[:id])

    invite_row = DB[:workspace_invites].where(email: "new@example.com").first
    expect(invite_row).not_to be_nil
    expect(invite_row[:invited_by]).to eq(user[:id])

    expect(Mail::TestMailer.deliveries.length).to eq(1)
    email = Mail::TestMailer.deliveries.first
    expect(email.to).to include("new@example.com")
    expect(email.subject).to include("Test Workspace")
  end

  it "rejects non-admin users" do
    member_user = TestFactories.user
    member_row = TestFactories.workspace_membership(workspace: workspace, user: member_user, role: "member")
    member_membership = WorkspaceMembership.find(member_row[:id])

    result = described_class.call(email: "new@example.com", workspace_id: workspace[:id], membership: member_membership)

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to include("not_admin_or_owner")
  end

  it "returns failure when email is empty" do
    result = described_class.call(email: "", workspace_id: workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Email is required")
  end

  it "returns failure when email is already a member" do
    existing = TestFactories.user(email: "existing@example.com")
    TestFactories.workspace_membership(workspace: workspace, user: existing)

    result = described_class.call(email: "existing@example.com", workspace_id: workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("This user is already a member of this workspace")
  end

  it "returns failure when a pending invite already exists" do
    described_class.call(email: "dupe@example.com", workspace_id: workspace[:id], membership: membership)

    result = described_class.call(email: "dupe@example.com", workspace_id: workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("An invitation has already been sent to this email")
  end

  it "logs info when invite is created" do
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    described_class.call(email: "log@example.com", workspace_id: workspace[:id], membership: membership)

    expect(logged_messages).to include(a_string_including("[Invites::Create]"))
  end
end
