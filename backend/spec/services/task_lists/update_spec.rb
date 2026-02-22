# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskLists::Update do
  it "returns failure when name is missing" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    list = TestFactories.task_list(workspace: workspace, user: user)

    result = described_class.call(task_list_id: list[:id], name: nil)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Name is required")
  end

  it "returns failure when task list not found" do
    result = described_class.call(task_list_id: SecureRandom.uuid, name: "New Name")

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Task list not found")
  end

  it "updates the task list name" do
    user = TestFactories.user
    workspace = TestFactories.workspace
    TestFactories.workspace_membership(workspace: workspace, user: user)
    list = TestFactories.task_list(workspace: workspace, user: user, name: "Old Name")

    result = described_class.call(task_list_id: list[:id], name: "New Name")

    expect(result.success?).to be true
    updated = result.value![:objects].find { |o| o[:objectType] == "taskList" }
    expect(updated[:name]).to eq("New Name")
  end
end
