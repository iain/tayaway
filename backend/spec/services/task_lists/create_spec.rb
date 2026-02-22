# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskLists::Create do
  it "returns failure when name is missing" do
    user = TestFactories.user
    workspace = TestFactories.workspace

    result = described_class.call(workspace_id: workspace[:id], user_id: user[:id], name: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "returns failure when name is empty" do
    user = TestFactories.user
    workspace = TestFactories.workspace

    result = described_class.call(workspace_id: workspace[:id], user_id: user[:id], name: "")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "creates task list and returns success" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    TestFactories.workspace_membership(workspace: workspace, user: user)

    result = described_class.call(workspace_id: workspace[:id], user_id: user[:id], name: "Shopping")

    expect(result.success?).to be true
    list = result.value![:objects].find { |o| o[:objectType] == "taskList" }
    expect(list[:name]).to eq("Shopping")
  end

  it "uses client-provided id when given" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    TestFactories.workspace_membership(workspace: workspace, user: user)
    client_id = SecureRandom.uuid

    result = described_class.call(workspace_id: workspace[:id], user_id: user[:id], name: "My List", id: client_id)

    expect(result.success?).to be true
    list = result.value![:objects].find { |o| o[:objectType] == "taskList" }
    expect(list[:id]).to eq(client_id)
  end

  it "returns existing list on idempotent replay with same id" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    TestFactories.workspace_membership(workspace: workspace, user: user)
    client_id = SecureRandom.uuid

    described_class.call(workspace_id: workspace[:id], user_id: user[:id], name: "My List", id: client_id)
    result2 = described_class.call(workspace_id: workspace[:id], user_id: user[:id], name: "My List", id: client_id)

    expect(result2.success?).to be true
    expect(DB[:task_lists].where(id: client_id).count).to eq(1)
  end
end
