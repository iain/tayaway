# frozen_string_literal: true

require "spec_helper"

RSpec.describe Invites::Cancel do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:membership_row) { TestFactories.workspace_membership(workspace: workspace, user: user, role: "admin") }
  let(:membership) { WorkspaceMembership.find(membership_row[:id]) }

  # -- test helper used across examples
  def create_invite(email: "cancel@example.com", accepted_at: nil)
    now = Time.now
    id = SecureRandom.uuid
    DB[:workspace_invites].insert(
      id: id,
      workspace_id: workspace[:id],
      invited_by: user[:id],
      email: email,
      token: Auth::Token.digest("token-#{id}"),
      expires_at: now + 3600,
      accepted_at: accepted_at,
      created_at: now,
      updated_at: now
    )
    id
  end
  it "rejects non-admin users" do
    invite_id = create_invite
    member_user = TestFactories.user
    member_row = TestFactories.workspace_membership(workspace: workspace, user: member_user, role: "member")
    member_membership = WorkspaceMembership.find(member_row[:id])

    result = described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: member_membership)

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to include("not_admin_or_owner")
    expect(DB[:workspace_invites].where(id: invite_id).count).to eq(1)
  end

  it "deletes a pending invite" do
    invite_id = create_invite

    result = described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([{ objectType: "workspaceInvite", id: invite_id }])
    expect(DB[:workspace_invites].where(id: invite_id).count).to eq(0)
    expect(DB[:deleted_items].where(object_type: "workspace_invite", object_id: invite_id).count).to eq(1)
  end

  it "returns failure for unknown invite" do
    result = described_class.call(invite_id: SecureRandom.uuid, workspace_id: workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invitation not found")
  end

  it "returns failure for invite in different workspace" do
    invite_id = create_invite
    other_workspace = TestFactories.workspace

    result = described_class.call(invite_id: invite_id, workspace_id: other_workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invitation not found")
  end

  it "returns failure for already accepted invite" do
    invite_id = create_invite(accepted_at: Time.now)

    result = described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("This invitation has already been accepted")
  end

  it "logs info when invite is cancelled" do
    invite_id = create_invite
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    expect(logged_messages).to include(a_string_including("[Invites::Cancel]"))
  end
end
