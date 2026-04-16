# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskItemSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:task_list_row) { TestFactories.task_list(workspace: workspace, user: user) }
      let(:task_item_row) { TestFactories.task_item(task_list: task_list_row, user: user) }
      let(:pool_object) { described_class.serialize_batch([TaskItem.find(task_item_row[:id])], pool: nil).first }

      it_behaves_like "a pool object with createdAt", "taskItem"
    end

    it "serializes task item fields" do
      task_list = TestFactories.task_list(workspace: workspace, user: user)
      task_item_row = TestFactories.task_item(
        task_list: task_list, user: user, content: "Buy cake", position: 1
      )
      task_item = TaskItem.find(task_item_row[:id])

      result = described_class.serialize_batch([task_item], pool: nil).first

      expect(result[:id]).to eq(task_item.id.to_s)
      expect(result[:objectType]).to eq("taskItem")
      expect(result[:taskListId]).to eq(task_list[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:content]).to eq("Buy cake")
      expect(result[:completedAt]).to be_nil
      expect(result[:position]).to eq(1)
    end
  end
end
