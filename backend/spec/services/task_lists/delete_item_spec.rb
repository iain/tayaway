# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskLists::DeleteItem do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:membership_row) { TestFactories.workspace_membership(workspace: workspace, user: user) }
  let(:membership) { WorkspaceMembership.find(membership_row[:id]) }
  let(:list) { TestFactories.task_list(workspace: workspace, user: user) }

  it "returns failure when task list not found" do
    item = TestFactories.task_item(task_list: list, user: user)

    result = described_class.call(task_list_id: SecureRandom.uuid, task_item_id: item[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Task list not found")
  end

  it "returns failure when task item not found" do
    result = described_class.call(task_list_id: list[:id], task_item_id: SecureRandom.uuid, membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Task item not found")
  end

  it "returns failure when item does not belong to the list" do
    other_list = TestFactories.task_list(workspace: workspace, user: user)
    item = TestFactories.task_item(task_list: other_list, user: user)

    result = described_class.call(task_list_id: list[:id], task_item_id: item[:id], membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Item does not belong to this list")
  end

  it "deletes the item and returns deleted payload" do
    item = TestFactories.task_item(task_list: list, user: user)

    result = described_class.call(task_list_id: list[:id], task_item_id: item[:id], membership: membership)

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([{ objectType: "taskItem", id: item[:id].to_s }])
    expect(DB[:task_items].where(id: item[:id]).count).to eq(0)
  end

  it "inserts a deleted_items record" do
    item = TestFactories.task_item(task_list: list, user: user)

    described_class.call(task_list_id: list[:id], task_item_id: item[:id], membership: membership)

    expect(DB[:deleted_items].where(object_type: "task_item", object_id: item[:id]).count).to eq(1)
  end
end
