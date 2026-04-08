# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::UpdateChore do
  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: e[:id]).update(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 7))
    DB[:events].where(id: e[:id]).first
  end
  let(:roster) { TestFactories.chore_roster(event: event, user: user) }
  let(:chore) { TestFactories.chore(chore_roster: roster, name: "Cooking", people_per_day: 1) }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  it "updates the name" do
    result = described_class.call(chore_id: chore[:id], workspace_id: workspace[:id], membership: membership_for(user), name: "Washing up")

    expect(result.success?).to be true
    updated = result.value![:objects].find { |o| o[:objectType] == "chore" }
    expect(updated[:name]).to eq("Washing up")
  end

  it "updates people_per_day" do
    result = described_class.call(chore_id: chore[:id], workspace_id: workspace[:id], membership: membership_for(user), people_per_day: 3)

    expect(result.success?).to be true
    updated = result.value![:objects].find { |o| o[:objectType] == "chore" }
    expect(updated[:peoplePerDay]).to eq(3)
  end

  it "updates position" do
    result = described_class.call(chore_id: chore[:id], workspace_id: workspace[:id], membership: membership_for(user), position: 5.0)

    expect(result.success?).to be true
    updated = result.value![:objects].find { |o| o[:objectType] == "chore" }
    expect(updated[:position]).to eq(5.0)
  end

  it "fails with empty name" do
    result = described_class.call(chore_id: chore[:id], workspace_id: workspace[:id], membership: membership_for(user), name: "")

    expect(result.failure?).to be true
    expect(result.failure.message).to include("empty")
  end

  it "fails with name over #{ValidationLimits::SHORT_STRING} characters" do
    result = described_class.call(chore_id: chore[:id], workspace_id: workspace[:id], membership: membership_for(user), name: "x" * (ValidationLimits::SHORT_STRING + 1))

    expect(result.failure?).to be true
    expect(result.failure.message).to include(ValidationLimits::SHORT_STRING.to_s)
  end

  it "fails with people_per_day out of range" do
    result = described_class.call(chore_id: chore[:id], workspace_id: workspace[:id], membership: membership_for(user), people_per_day: 0)

    expect(result.failure?).to be true
    expect(result.failure.message).to include("between 1 and #{ValidationLimits::PEOPLE_PER_DAY_MAX}")
  end

  it "fails when no changes provided" do
    result = described_class.call(chore_id: chore[:id], workspace_id: workspace[:id], membership: membership_for(user))

    expect(result.failure?).to be true
    expect(result.failure.message).to include("No changes")
  end

  it "fails for nonexistent chore" do
    result = described_class.call(chore_id: SecureRandom.uuid, workspace_id: workspace[:id], membership: membership_for(user), name: "New")

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
  end
end
