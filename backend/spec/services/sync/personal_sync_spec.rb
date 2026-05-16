# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sync::PersonalSync do
  let(:user) { TestFactories.user }
  let(:workspace_a) { TestFactories.workspace(name: "Workspace A") }
  let(:workspace_b) { TestFactories.workspace(name: "Workspace B") }
  let(:other_workspace) { TestFactories.workspace(name: "Stranger Workspace") }
  let(:other_user) { TestFactories.user }

  let!(:membership_a) { TestFactories.workspace_membership(workspace: workspace_a, user: user, role: "owner") }
  let!(:membership_b) { TestFactories.workspace_membership(workspace: workspace_b, user: user, role: "member") }
  let!(:other_membership) { TestFactories.workspace_membership(workspace: other_workspace, user: other_user, role: "owner") }

  it "returns every workspace the user belongs to" do
    result = described_class.call(user_id: user[:id])

    workspace_ids = result[:objects].select { |o| o[:objectType] == "workspace" }.map { |o| o[:id] }
    expect(workspace_ids).to contain_exactly(workspace_a[:id].to_s, workspace_b[:id].to_s)
  end

  it "returns the user's own memberships across all their workspaces" do
    result = described_class.call(user_id: user[:id])

    membership_ids = result[:objects].select { |o| o[:objectType] == "member" }.map { |o| o[:id] }
    expect(membership_ids).to contain_exactly(membership_a[:id], membership_b[:id])
  end

  it "does not include workspaces or memberships the user is not part of" do
    result = described_class.call(user_id: user[:id])

    all_ids = result[:objects].map { |o| o[:id] }
    expect(all_ids).not_to include(other_workspace[:id].to_s)
    expect(all_ids).not_to include(other_membership[:id])
  end

  it "tags the sync type as personal and stamps syncedAt" do
    result = described_class.call(user_id: user[:id])

    expect(result[:syncType]).to eq("personal")
    expect(result[:syncedAt]).not_to be_nil
  end

  it "includes the user's recent notification backlog so unread badges hydrate on connect" do
    notification_row = TestFactories.notification(user: user, workspace: workspace_a, kind: "test_event")

    result = described_class.call(user_id: user[:id])

    notification = result[:objects].find { |o| o[:objectType] == "notification" }
    expect(notification).not_to be_nil
    expect(notification[:id]).to eq(notification_row[:id].to_s)
    expect(notification[:workspaceId]).to eq(workspace_a[:id].to_s)
  end

  it "does not include other users' notifications" do
    TestFactories.notification(user: other_user, workspace: other_workspace, kind: "test_event")

    result = described_class.call(user_id: user[:id])

    notifications = result[:objects].select { |o| o[:objectType] == "notification" }
    expect(notifications).to be_empty
  end

  it "returns an empty pool for a user with no memberships" do
    loner = TestFactories.user

    result = described_class.call(user_id: loner[:id])

    expect(result[:objects]).to eq([])
  end
end
