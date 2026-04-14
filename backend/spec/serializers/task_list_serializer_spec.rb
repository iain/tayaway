# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskListSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      let(:task_list_row) { TestFactories.task_list(workspace: workspace, user: user) }
      let(:pool_object) { described_class.serialize_batch([TaskList.find(task_list_row[:id])], pool: nil).first }

      subject { pool_object }

      it_behaves_like "a pool object with createdAt", "taskList"
    end

    it "serializes task list fields" do
      task_list_row = TestFactories.task_list(workspace: workspace, user: user, name: "Groceries")
      task_list = TaskList.find(task_list_row[:id])

      result = described_class.serialize_batch([task_list], pool: nil).first

      expect(result[:id]).to eq(task_list.id.to_s)
      expect(result[:objectType]).to eq("taskList")
      expect(result[:workspaceId]).to eq(workspace[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:name]).to eq("Groceries")
    end

    it "adds child task_items to the pool when pool is provided" do
      TestFactories.workspace_membership(workspace: workspace, user: user)
      task_list_row = TestFactories.task_list(workspace: workspace, user: user)
      item1 = TestFactories.task_item(task_list: task_list_row, user: user, content: "milk")
      item2 = TestFactories.task_item(task_list: task_list_row, user: user, content: "bread")
      task_list = TaskList.find(task_list_row[:id])

      pool = PoolSerializer.new(workspace_id: workspace[:id])
      pool.add(:task_list, [task_list])

      items = pool.to_a.select { |o| o[:objectType] == "taskItem" }
      expect(items.map { |o| o[:id] }).to contain_exactly(item1[:id].to_s, item2[:id].to_s)
    end

    it "does not add children when pool is nil" do
      task_list_row = TestFactories.task_list(workspace: workspace, user: user)
      TestFactories.task_item(task_list: task_list_row, user: user)
      task_list = TaskList.find(task_list_row[:id])

      expect { described_class.serialize_batch([task_list], pool: nil) }.not_to raise_error
    end
  end
end
