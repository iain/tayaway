# frozen_string_literal: true

require "spec_helper"

RSpec.describe Invites::Remind do
  let(:workspace) { TestFactories.workspace(name: "Camp Workspace") }
  let(:user) { TestFactories.user }
  let(:membership_row) { TestFactories.workspace_membership(workspace: workspace, user: user, role: "admin") }
  let(:membership) { WorkspaceMembership.find(membership_row[:id]) }

  # -- test helper used across examples
  def create_invite(accepted_at: nil, last_reminded_at: nil, created_at: nil)
    id = SecureRandom.uuid
    now = Time.now
    created_at ||= now
    DB[:workspace_invites].insert(
      id: id,
      workspace_id: workspace[:id],
      invited_by: user[:id],
      email: "invitee@example.com",
      token: Auth::Token.digest("token-#{id}"),
      expires_at: now + 3600,
      accepted_at: accepted_at,
      last_reminded_at: last_reminded_at,
      created_at: created_at,
      updated_at: created_at
    )
    id
  end
  it "returns failure when invite_id is nil" do
    result = described_class.call(invite_id: nil, workspace_id: workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Invite ID is required")
  end

  it "returns 404 when invite not found" do
    result = described_class.call(invite_id: SecureRandom.uuid, workspace_id: workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
    expect(result.failure.message).to eq("Invitation not found")
  end

  it "returns 404 when invite belongs to a different workspace" do
    other_workspace = TestFactories.workspace
    invite_id = create_invite

    result = described_class.call(invite_id: invite_id, workspace_id: other_workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
    expect(result.failure.message).to eq("Invitation not found")
  end

  it "returns failure when invite is already accepted" do
    invite_id = create_invite(accepted_at: Time.now)

    result = described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("This invitation has already been accepted")
  end

  it "returns failure when cooldown has not elapsed since creation" do
    invite_id = create_invite(created_at: Time.now - 3600) # 1 hour ago, cooldown is 24h

    result = described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("A reminder was already sent recently. Please wait before sending another.")
  end

  it "returns failure when cooldown has not elapsed since last reminder" do
    invite_id = create_invite(
      created_at: Time.now - (48 * 3600), # 2 days ago
      last_reminded_at: Time.now - 3600   # 1 hour ago
    )

    result = described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("A reminder was already sent recently. Please wait before sending another.")
  end

  it "resends the invite when cooldown has elapsed since creation" do
    invite_id = create_invite(created_at: Time.now - (25 * 3600)) # 25 hours ago

    result = described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    expect(result.success?).to be true
    obj = result.value![:objects].find { |o| o[:objectType] == "workspaceInvite" }
    expect(obj[:email]).to eq("invitee@example.com")
    expect(obj[:lastRemindedAt]).not_to be_nil
  end

  it "resends the invite when cooldown has elapsed since last reminder" do
    invite_id = create_invite(
      created_at: Time.now - (72 * 3600),       # 3 days ago
      last_reminded_at: Time.now - (25 * 3600)  # 25 hours ago — past 24h cooldown
    )

    result = described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    expect(result.success?).to be true
    obj = result.value![:objects].find { |o| o[:objectType] == "workspaceInvite" }
    expect(obj[:email]).to eq("invitee@example.com")
    expect(obj[:lastRemindedAt]).not_to be_nil
  end

  it "returns failure when just inside the 24h cooldown boundary since creation" do
    # 23h59m ago — comfortably inside the cooldown window, must be blocked
    invite_id = create_invite(created_at: Time.now - ((24 * 3600) - 60))

    result = described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("A reminder was already sent recently. Please wait before sending another.")
  end

  it "returns failure when just inside the 24h cooldown boundary since last reminder" do
    # last_reminded_at was 23h59m ago — comfortably inside the cooldown window
    invite_id = create_invite(
      created_at: Time.now - (48 * 3600),
      last_reminded_at: Time.now - ((24 * 3600) - 60)
    )

    result = described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("A reminder was already sent recently. Please wait before sending another.")
  end

  it "sends an email when reminder is successful" do
    invite_id = create_invite(created_at: Time.now - (25 * 3600))

    described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    expect(Mail::TestMailer.deliveries.length).to eq(1)
    email = Mail::TestMailer.deliveries.first
    expect(email.to).to include("invitee@example.com")
    expect(email.subject).to include("Camp Workspace")
  end

  it "updates last_reminded_at and regenerates token" do
    invite_id = create_invite(created_at: Time.now - (25 * 3600))
    old_token = DB[:workspace_invites].where(id: invite_id).first[:token]

    described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    row = DB[:workspace_invites].where(id: invite_id).first
    expect(row[:last_reminded_at]).not_to be_nil
    expect(row[:token]).not_to eq(old_token)
  end

  it "logs info when reminder is sent" do
    invite_id = create_invite(created_at: Time.now - (25 * 3600))
    logged_messages = []
    allow(APP_LOGGER).to receive(:info) do |&block|
      logged_messages << block.call if block
    end

    described_class.call(invite_id: invite_id, workspace_id: workspace[:id], membership: membership)

    expect(logged_messages).to include(a_string_including("[Invites::Remind]"))
  end
end
