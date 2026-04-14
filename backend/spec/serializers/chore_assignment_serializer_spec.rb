# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreAssignmentSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "serializes assignment fields" do
      event = TestFactories.event(workspace: workspace, user: user)
      roster = TestFactories.chore_roster(event: event, user: user)
      chore = TestFactories.chore(chore_roster: roster, name: "Wash up")
      assignment = TestFactories.chore_assignment(chore: chore, user: user, date: Date.today, pinned: true, note: "dish soap")
      assignment_model = ChoreAssignment.find(assignment[:id])

      result = described_class.serialize_batch([assignment_model], pool: nil).first

      expect(result[:id]).to eq(assignment[:id].to_s)
      expect(result[:objectType]).to eq("choreAssignment")
      expect(result[:choreId]).to eq(chore[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:date]).to eq(Date.today.iso8601)
      expect(result[:pinned]).to be true
      expect(result[:note]).to eq("dish soap")
    end
  end
end
