# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskLists::Update do
  it "returns failure when neither name nor position is provided" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
    membership = WorkspaceMembership.find(membership_row[:id])
    list = TestFactories.task_list(workspace: workspace, user: user)

    result = described_class.call(task_list_id: list[:id], name: nil, membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name or position is required")
  end

  it "returns failure when task list not found" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
    membership = WorkspaceMembership.find(membership_row[:id])

    result = described_class.call(task_list_id: SecureRandom.uuid, name: "New Name", membership: membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Task list not found")
  end

  it "updates the task list name" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
    membership = WorkspaceMembership.find(membership_row[:id])
    list = TestFactories.task_list(workspace: workspace, user: user, name: "Old Name")

    result = described_class.call(task_list_id: list[:id], name: "New Name", membership: membership)

    expect(result.success?).to be true
    updated = result.value![:objects].find { |o| o[:objectType] == "taskList" }
    expect(updated[:name]).to eq("New Name")
  end
end
