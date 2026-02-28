# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::CreateAssignment do
  let(:user) { TestFactories.user }
  let(:assignee) { TestFactories.user(name: "Assignee") }
  let(:workspace) { TestFactories.workspace }
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: e[:id]).update(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 7))
    DB[:events].where(id: e[:id]).first
  end
  let(:roster) { TestFactories.chore_roster(event: event, user: user) }
  let(:chore) { TestFactories.chore(chore_roster: roster, name: "Cooking") }

  it "creates a pinned assignment" do
    result = described_class.call(
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      chore_id: chore[:id].to_s,
      user_id: assignee[:id].to_s,
      date: "2026-03-02",
      note: "Pizza night"
    )

    expect(result.success?).to be true
    assignment = result.value![:objects].find { |o| o[:objectType] == "choreAssignment" }
    expect(assignment[:pinned]).to be true
    expect(assignment[:note]).to eq("Pizza night")
    expect(assignment[:userId]).to eq(assignee[:id].to_s)
  end

  it "fails when date is outside event range" do
    result = described_class.call(
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      chore_id: chore[:id].to_s,
      user_id: assignee[:id].to_s,
      date: "2026-04-01"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to include("within event date range")
  end

  it "fails when chore doesn't belong to roster" do
    other_roster = TestFactories.chore_roster(
      event: (
        e = TestFactories.event(workspace: workspace, user: user)
        DB[:events].where(id: e[:id]).update(start_date: Date.new(2026, 4, 1), end_date: Date.new(2026, 4, 7))
        DB[:events].where(id: e[:id]).first
      ),
      user: user
    )
    other_chore = TestFactories.chore(chore_roster: other_roster)

    result = described_class.call(
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      chore_id: other_chore[:id].to_s,
      user_id: assignee[:id].to_s,
      date: "2026-03-02"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to include("not found")
  end
end
