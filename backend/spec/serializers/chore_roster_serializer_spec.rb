# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosterSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:event_row) { TestFactories.event(workspace: workspace, user: user) }
      let(:roster_row) { TestFactories.chore_roster(event: event_row, user: user) }
      let(:pool_object) do
        pool = PoolSerializer.new(workspace_id: workspace[:id])
        described_class.serialize_batch([ChoreRoster.find(roster_row[:id])], pool: pool).first
      end

      it_behaves_like "a pool object with createdAt", "choreRoster"
    end

    it "serializes roster fields with batched choreIds" do
      event = TestFactories.event(workspace: workspace, user: user)
      roster_row = TestFactories.chore_roster(event: event, user: user)
      chore_row = TestFactories.chore(chore_roster: roster_row)
      roster = ChoreRoster.find(roster_row[:id])
      pool = PoolSerializer.new(workspace_id: workspace[:id])

      result = described_class.serialize_batch([roster], pool: pool).first

      expect(result[:id]).to eq(roster.id.to_s)
      expect(result[:objectType]).to eq("choreRoster")
      expect(result[:eventId]).to eq(event[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:choreIds]).to include(chore_row[:id].to_s)
    end

    it "raises when pool is nil — child expansion would be silently skipped" do
      event = TestFactories.event(workspace: workspace, user: user)
      roster_row = TestFactories.chore_roster(event: event, user: user)
      roster = ChoreRoster.find(roster_row[:id])

      expect { described_class.serialize_batch([roster], pool: nil) }
        .to raise_error(ArgumentError, /requires a non-nil pool/)
    end

    it "adds chores and assignments to the pool" do
      event = TestFactories.event(workspace: workspace, user: user)
      roster_row = TestFactories.chore_roster(event: event, user: user)
      chore_row = TestFactories.chore(chore_roster: roster_row)
      assignment_row = TestFactories.chore_assignment(chore: chore_row, user: user, date: Date.today)
      roster = ChoreRoster.find(roster_row[:id])

      pool = PoolSerializer.new(workspace_id: workspace[:id])
      pool.add(:chore_roster, [roster])

      objects = pool.to_a
      expect(objects.map { |o| o[:objectType] }).to include("choreRoster", "chore", "choreAssignment")
      expect(objects.find { |o| o[:objectType] == "chore" }[:id]).to eq(chore_row[:id].to_s)
      expect(objects.find { |o| o[:objectType] == "choreAssignment" }[:id]).to eq(assignment_row[:id].to_s)
    end
  end
end
