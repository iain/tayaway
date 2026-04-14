# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:event_row) { TestFactories.event(workspace: workspace, user: user) }
      let(:roster_row) { TestFactories.chore_roster(event: event_row, user: user) }
      let(:chore_row) { TestFactories.chore(chore_roster: roster_row) }
      let(:pool_object) { described_class.serialize_batch([Chore.find(chore_row[:id])], pool: nil).first }

      it_behaves_like "a pool object with createdAt", "chore"
    end

    it "serializes chore fields with batched assignmentIds" do
      event = TestFactories.event(workspace: workspace, user: user)
      roster = TestFactories.chore_roster(event: event, user: user)
      chore_row = TestFactories.chore(chore_roster: roster, name: "Cook", people_per_day: 2, position: 0)
      assignment = TestFactories.chore_assignment(chore: chore_row, user: user, date: Date.today)
      chore = Chore.find(chore_row[:id])

      result = described_class.serialize_batch([chore], pool: nil).first

      expect(result[:id]).to eq(chore.id.to_s)
      expect(result[:objectType]).to eq("chore")
      expect(result[:choreRosterId]).to eq(roster[:id].to_s)
      expect(result[:name]).to eq("Cook")
      expect(result[:peoplePerDay]).to eq(2)
      expect(result[:position]).to eq(0)
      expect(result[:assignmentIds]).to include(assignment[:id].to_s)
    end
  end
end
