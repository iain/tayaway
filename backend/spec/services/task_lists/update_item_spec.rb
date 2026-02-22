# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskLists::UpdateItem do
  it "returns failure when item not found" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    list = TestFactories.task_list(workspace: workspace, user: user)

    result = described_class.call(task_list_id: list[:id], task_item_id: SecureRandom.uuid, completed: true)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Task item not found")
  end

  it "returns failure when item does not belong to list" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    list1 = TestFactories.task_list(workspace: workspace, user: user)
    list2 = TestFactories.task_list(workspace: workspace, user: user)
    item = TestFactories.task_item(task_list: list2, user: user)

    result = described_class.call(task_list_id: list1[:id], task_item_id: item[:id], completed: true)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Item does not belong to this list")
  end

  it "marks item as completed" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    TestFactories.workspace_membership(workspace: workspace, user: user)
    list = TestFactories.task_list(workspace: workspace, user: user)
    item = TestFactories.task_item(task_list: list, user: user)

    result = described_class.call(task_list_id: list[:id], task_item_id: item[:id], completed: true)

    expect(result.success?).to be true
    updated_item = result.value![:objects].find { |o| o[:objectType] == "taskItem" && o[:id] == item[:id] }
    expect(updated_item[:completedAt]).not_to be_nil
  end

  it "marks item as not completed" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    TestFactories.workspace_membership(workspace: workspace, user: user)
    list = TestFactories.task_list(workspace: workspace, user: user)
    item = TestFactories.task_item(task_list: list, user: user, completed_at: Time.now)

    result = described_class.call(task_list_id: list[:id], task_item_id: item[:id], completed: false)

    expect(result.success?).to be true
    updated_item = result.value![:objects].find { |o| o[:objectType] == "taskItem" && o[:id] == item[:id] }
    expect(updated_item[:completedAt]).to be_nil
  end

  it "updates item content" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    TestFactories.workspace_membership(workspace: workspace, user: user)
    list = TestFactories.task_list(workspace: workspace, user: user)
    item = TestFactories.task_item(task_list: list, user: user, content: "Old content")

    result = described_class.call(task_list_id: list[:id], task_item_id: item[:id], content: "New content")

    expect(result.success?).to be true
    updated_item = result.value![:objects].find { |o| o[:objectType] == "taskItem" && o[:id] == item[:id] }
    expect(updated_item[:content]).to eq("New content")
  end
end
