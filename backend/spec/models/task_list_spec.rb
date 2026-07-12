# frozen_string_literal: true

require "spec_helper"

RSpec.describe TaskList do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".for_workspace" do
    it "breaks position ties by created_at, then name, then id" do
      id_a = "aaaaaaaa-2222-4000-8000-000000000000"
      id_b = "bbbbbbbb-2222-4000-8000-000000000000"
      id_c = "cccccccc-2222-4000-8000-000000000000"
      id_f = "ffffffff-2222-4000-8000-000000000000"

      # All four keep the column default position, so they all tie. Insert
      # in scrambled order so a stable insert-order scan can't pass by
      # accident. a is created earliest; the other three tie on
      # created_at: f's name sorts first despite the highest id, and b/c
      # share a name so id decides.
      TestFactories.task_list(workspace: workspace, user: user, id: id_c, name: "Groceries")
      TestFactories.task_list(workspace: workspace, user: user, id: id_f, name: "Errands")
      TestFactories.task_list(workspace: workspace, user: user, id: id_b, name: "Groceries")
      TestFactories.task_list(workspace: workspace, user: user, id: id_a, name: "Packing")

      early = Time.utc(2026, 1, 1, 12, 0, 0)
      late = Time.utc(2026, 1, 1, 12, 0, 5)
      DB[:task_lists].where(id: id_a).update(created_at: early)
      DB[:task_lists].where(id: [id_b, id_c, id_f]).update(created_at: late)

      ordered = described_class.for_workspace(workspace[:id]).map { |l| l.id.to_s }
      expect(ordered).to eq([id_a, id_f, id_b, id_c])
    end
  end
end
