# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreAssignmentSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      let(:event_row) { TestFactories.event(workspace: workspace, user: user) }
      let(:roster_row) { TestFactories.chore_roster(event: event_row, user: user) }
      let(:chore_row) { TestFactories.chore(chore_roster: roster_row) }
      let(:assignment_row) { TestFactories.chore_assignment(chore: chore_row, user: user, date: Date.today) }
      let(:pool_object) { described_class.serialize_batch([ChoreAssignment.find(assignment_row[:id])], pool: nil).first }

      subject { pool_object }

      it_behaves_like "a pool object with createdAt", "choreAssignment"
    end

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
