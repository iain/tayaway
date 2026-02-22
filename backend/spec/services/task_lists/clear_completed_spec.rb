# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskLists::ClearCompleted do
  it "returns failure when task list not found" do
    result = described_class.call(task_list_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Task list not found")
  end

  it "does nothing when no completed items" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    list = TestFactories.task_list(workspace: workspace, user: user)
    TestFactories.task_item(task_list: list, user: user)

    result = described_class.call(task_list_id: list[:id])

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([])
    expect(DB[:task_items].where(task_list_id: list[:id]).count).to eq(1)
  end

  it "deletes all completed items" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    list = TestFactories.task_list(workspace: workspace, user: user)
    item1 = TestFactories.task_item(task_list: list, user: user, completed_at: Time.now)
    item2 = TestFactories.task_item(task_list: list, user: user, completed_at: Time.now)
    TestFactories.task_item(task_list: list, user: user) # not completed

    result = described_class.call(task_list_id: list[:id])

    expect(result.success?).to be true
    expect(result.value![:deleted].map { |d| d[:id] }).to contain_exactly(item1[:id], item2[:id])
    expect(DB[:task_items].where(task_list_id: list[:id]).count).to eq(1)
  end

  it "inserts deleted_items records for cleared items" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    list = TestFactories.task_list(workspace: workspace, user: user)
    item = TestFactories.task_item(task_list: list, user: user, completed_at: Time.now)

    described_class.call(task_list_id: list[:id])

    expect(DB[:deleted_items].where(object_type: "task_item", object_id: item[:id]).count).to eq(1)
  end
end
