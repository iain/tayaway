# frozen_string_literal: true

require "spec_helper"

RSpec.describe Sync::WorkspaceSync do
  let(:workspace) { TestFactories.workspace(name: "My Workspace") }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  it "returns empty response when workspace not found" do
    result = described_class.call(workspace_id: SecureRandom.uuid)

    expect(result[:objects]).to eq([])
    expect(result[:deleted]).to eq([])
    expect(result[:syncType]).to eq("full")
    expect(result[:syncedAt]).not_to be_nil
  end

  it "returns full sync with workspace object" do
    result = described_class.call(workspace_id: workspace[:id])

    expect(result[:syncType]).to eq("full")
    ws_obj = result[:objects].find { |o| o[:objectType] == "workspace" }
    expect(ws_obj).not_to be_nil
    expect(ws_obj[:name]).to eq("My Workspace")
  end

  it "includes members in the response" do
    result = described_class.call(workspace_id: workspace[:id])

    member_obj = result[:objects].find { |o| o[:objectType] == "member" }
    expect(member_obj).not_to be_nil
    expect(member_obj[:userId]).to eq(user[:id].to_s)
  end

  it "includes events in the response" do
    TestFactories.event(workspace: workspace, user: user, name: "Birthday Party")

    result = described_class.call(workspace_id: workspace[:id])

    event_obj = result[:objects].find { |o| o[:objectType] == "event" }
    expect(event_obj).not_to be_nil
    expect(event_obj[:name]).to eq("Birthday Party")
  end

  it "returns deleted items on partial sync" do
    event = TestFactories.event(workspace: workspace, user: user)
    event_id = event[:id].to_s
    since = Time.now - 60

    DB[:deleted_items].insert(
      workspace_id: workspace[:id],
      object_type: "event",
      object_id: event_id,
      deleted_at: Time.now
    )

    result = described_class.call(workspace_id: workspace[:id], since: since)

    expect(result[:syncType]).to eq("partial")
    expect(result[:deleted]).to include(hash_including(objectType: "event", id: event_id))
  end

  it "forces a full sync when since is older than retention period" do
    old_since = Time.now - (8 * 24 * 60 * 60) # 8 days ago

    result = described_class.call(workspace_id: workspace[:id], since: old_since)

    expect(result[:syncType]).to eq("full")
    expect(result[:deleted]).to eq([])
  end

  it "performs a partial sync when since is within retention period" do
    since = Time.now - 60

    result = described_class.call(workspace_id: workspace[:id], since: since)

    expect(result[:syncType]).to eq("partial")
  end
end
