# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::AddChore do
  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: e[:id]).update(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 7))
    DB[:events].where(id: e[:id]).first
  end
  let(:roster) { TestFactories.chore_roster(event: event, user: user) }

  it "adds a chore to the roster" do
    result = described_class.call(
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      name: "Cooking",
      people_per_day: 2
    )

    expect(result.success?).to be true
    chore = result.value![:objects].find { |o| o[:objectType] == "chore" }
    expect(chore[:name]).to eq("Cooking")
    expect(chore[:peoplePerDay]).to eq(2)
  end

  it "fails with empty name" do
    result = described_class.call(
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      name: "",
      people_per_day: 1
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to include("Name")
  end

  it "is idempotent with client ID" do
    chore_id = SecureRandom.uuid

    result1 = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], name: "Test", people_per_day: 1, id: chore_id)
    result2 = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id], name: "Test", people_per_day: 1, id: chore_id)

    expect(result1.success?).to be true
    expect(result2.success?).to be true
    expect(DB[:chores].where(id: chore_id).count).to eq(1)
  end
end
