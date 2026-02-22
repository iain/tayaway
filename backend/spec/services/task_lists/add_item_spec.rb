# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskLists::AddItem do
  it "returns failure when content is missing" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    list = TestFactories.task_list(workspace: workspace, user: user)

    result = described_class.call(task_list_id: list[:id], user_id: user[:id], content: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Content is required")
  end

  it "returns failure when task list not found" do
    user = TestFactories.user
    result = described_class.call(task_list_id: SecureRandom.uuid, user_id: user[:id], content: "Do thing")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Task list not found")
  end

  it "adds item to the task list" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    TestFactories.workspace_membership(workspace: workspace, user: user)
    list = TestFactories.task_list(workspace: workspace, user: user)

    result = described_class.call(task_list_id: list[:id], user_id: user[:id], content: "Buy milk")

    expect(result.success?).to be true
    task_list = result.value![:objects].find { |o| o[:objectType] == "taskList" }
    expect(task_list[:itemIds].length).to eq(1)
    item = result.value![:objects].find { |o| o[:objectType] == "taskItem" }
    expect(item[:content]).to eq("Buy milk")
    expect(item[:completedAt]).to be_nil
  end

  it "is idempotent with client-provided id" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    TestFactories.workspace_membership(workspace: workspace, user: user)
    list = TestFactories.task_list(workspace: workspace, user: user)
    item_id = SecureRandom.uuid

    described_class.call(task_list_id: list[:id], user_id: user[:id], content: "Buy milk", id: item_id)
    result2 = described_class.call(task_list_id: list[:id], user_id: user[:id], content: "Buy milk", id: item_id)

    expect(result2.success?).to be true
    expect(DB[:task_items].where(id: item_id).count).to eq(1)
  end
end
