# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::DeleteRoster do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: e[:id]).update(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 7))
    DB[:events].where(id: e[:id]).first
  end
  let(:roster) { TestFactories.chore_roster(event: event, user: user) }

  def membership_for(u)
    row = TestFactories.workspace_membership(workspace: workspace, user: u)
    WorkspaceMembership.find(row[:id])
  end

  it "deletes the roster" do
    roster_id = roster[:id]

    result = described_class.call(roster_id: roster_id, membership: membership_for(user), workspace_id: workspace[:id])

    expect(result.success?).to be true
    expect(DB[:chore_rosters].where(id: roster_id).count).to eq(0)
  end

  it "cascades deletion to chores and assignments" do
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking")
    assignment = TestFactories.chore_assignment(chore: chore, user: user, date: Date.new(2026, 3, 1))

    result = described_class.call(roster_id: roster[:id], membership: membership_for(user), workspace_id: workspace[:id])

    expect(result.success?).to be true
    expect(DB[:chores].where(id: chore[:id]).count).to eq(0)
    expect(DB[:chore_assignments].where(id: assignment[:id]).count).to eq(0)
  end

  it "tracks all deletions in deleted_items" do
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking")
    TestFactories.chore_assignment(chore: chore, user: user, date: Date.new(2026, 3, 1))

    described_class.call(roster_id: roster[:id], membership: membership_for(user), workspace_id: workspace[:id])

    expect(DB[:deleted_items].where(object_type: "chore_roster", object_id: roster[:id]).count).to eq(1)
    expect(DB[:deleted_items].where(object_type: "chore", object_id: chore[:id]).count).to eq(1)
    expect(DB[:deleted_items].where(object_type: "chore_assignment").count).to eq(1)
  end

  it "returns deleted items in response" do
    chore = TestFactories.chore(chore_roster: roster, name: "Cooking")
    assignment = TestFactories.chore_assignment(chore: chore, user: user, date: Date.new(2026, 3, 1))

    result = described_class.call(roster_id: roster[:id], membership: membership_for(user), workspace_id: workspace[:id])

    deleted = result.value![:deleted]
    types = deleted.map { |d| d[:objectType] }
    expect(types).to include("choreRoster", "chore", "choreAssignment")
    expect(deleted.find { |d| d[:objectType] == "choreRoster" }[:id]).to eq(roster[:id].to_s)
    expect(deleted.find { |d| d[:objectType] == "chore" }[:id]).to eq(chore[:id].to_s)
    expect(deleted.find { |d| d[:objectType] == "choreAssignment" }[:id]).to eq(assignment[:id].to_s)
  end

  it "rejects non-creator" do
    other_user = TestFactories.user(email: "other@example.com")

    result = described_class.call(roster_id: roster[:id], membership: membership_for(other_user), workspace_id: workspace[:id])

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
  end

  it "fails for nonexistent roster" do
    result = described_class.call(roster_id: SecureRandom.uuid, membership: membership_for(user), workspace_id: workspace[:id])

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
  end
end
