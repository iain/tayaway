# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskItem do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:list) { TestFactories.task_list(workspace: workspace, user: user) }

  # Concurrent adds both read the same max position, so ties are a normal
  # occurrence. The order must still be deterministic: created_at, then
  # content, then id.
  describe ".for_task_list" do
    it "breaks position ties by created_at, then content, then id" do
      id_a = "aaaaaaaa-0000-4000-8000-000000000000"
      id_b = "bbbbbbbb-0000-4000-8000-000000000000"
      id_c = "cccccccc-0000-4000-8000-000000000000"
      id_f = "ffffffff-0000-4000-8000-000000000000"

      # Insert in scrambled order so a stable insert-order scan can't pass
      # by accident. All four share the same position; a is created
      # earliest, the other three tie on created_at: f's content sorts
      # first despite the highest id, and b/c share content so id decides.
      TestFactories.task_item(task_list: list, user: user, position: 1.0, id: id_c, content: "bananas")
      TestFactories.task_item(task_list: list, user: user, position: 1.0, id: id_f, content: "apples")
      TestFactories.task_item(task_list: list, user: user, position: 1.0, id: id_b, content: "bananas")
      TestFactories.task_item(task_list: list, user: user, position: 1.0, id: id_a, content: "cherries")

      early = Time.utc(2026, 1, 1, 12, 0, 0)
      late = Time.utc(2026, 1, 1, 12, 0, 5)
      DB[:task_items].where(id: id_a).update(created_at: early)
      DB[:task_items].where(id: [id_b, id_c, id_f]).update(created_at: late)

      ordered = described_class.for_task_list(list[:id]).map { |item| item.id.to_s }
      expect(ordered).to eq([id_a, id_f, id_b, id_c])
    end
  end

  describe ".for_task_lists" do
    it "breaks position, created_at, and content ties by id within each list" do
      id_b = "bbbbbbbb-1111-4000-8000-000000000000"
      id_a = "aaaaaaaa-1111-4000-8000-000000000000"
      TestFactories.task_item(task_list: list, user: user, position: 1.0, id: id_b, content: "same")
      TestFactories.task_item(task_list: list, user: user, position: 1.0, id: id_a, content: "same")
      same_time = Time.utc(2026, 1, 1, 12, 0, 0)
      DB[:task_items].where(id: [id_a, id_b]).update(created_at: same_time)

      ordered = described_class.for_task_lists([list[:id]]).map { |item| item.id.to_s }
      expect(ordered).to eq([id_a, id_b])
    end
  end
end
