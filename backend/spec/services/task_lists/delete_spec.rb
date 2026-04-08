# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskLists::Delete do
  it "returns failure when task list not found" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
    membership = WorkspaceMembership.find(membership_row[:id])

    result = described_class.call(task_list_id: SecureRandom.uuid, membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Task list not found")
  end

  it "deletes the task list and cascades items" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
    membership = WorkspaceMembership.find(membership_row[:id])
    list = TestFactories.task_list(workspace: workspace, user: user)
    TestFactories.task_item(task_list: list, user: user)

    result = described_class.call(task_list_id: list[:id], membership: membership)

    expect(result.success?).to be true
    expect(result.value![:deleted]).to include(hash_including(objectType: "taskList", id: list[:id]))
    expect(DB[:task_lists].where(id: list[:id]).count).to eq(0)
    expect(DB[:task_items].where(task_list_id: list[:id]).count).to eq(0)
  end

  it "inserts deleted_items record" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
    membership = WorkspaceMembership.find(membership_row[:id])
    list = TestFactories.task_list(workspace: workspace, user: user)

    described_class.call(task_list_id: list[:id], membership: membership)

    expect(DB[:deleted_items].where(object_type: "task_list", object_id: list[:id]).count).to eq(1)
  end
end
