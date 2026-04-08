# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::DeleteChore do
  let(:user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:event) do
    e = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: e[:id]).update(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 7))
    DB[:events].where(id: e[:id]).first
  end
  let(:roster) { TestFactories.chore_roster(event: event, user: user) }
  let(:chore) { TestFactories.chore(chore_roster: roster, name: "Cooking") }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  it "deletes the chore" do
    chore_id = chore[:id]

    result = described_class.call(chore_id: chore_id, roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user))

    expect(result.success?).to be true
    expect(DB[:chores].where(id: chore_id).count).to eq(0)
  end

  it "cascades deletion to assignments" do
    assignment = TestFactories.chore_assignment(chore: chore, user: user, date: Date.new(2026, 3, 1))

    result = described_class.call(chore_id: chore[:id], roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user))

    expect(result.success?).to be true
    expect(DB[:chore_assignments].where(id: assignment[:id]).count).to eq(0)
  end

  it "tracks deletions in deleted_items" do
    TestFactories.chore_assignment(chore: chore, user: user, date: Date.new(2026, 3, 1))

    described_class.call(chore_id: chore[:id], roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user))

    expect(DB[:deleted_items].where(object_type: "chore", object_id: chore[:id]).count).to eq(1)
    expect(DB[:deleted_items].where(object_type: "chore_assignment").count).to eq(1)
  end

  it "returns deleted items in response" do
    assignment = TestFactories.chore_assignment(chore: chore, user: user, date: Date.new(2026, 3, 1))

    result = described_class.call(chore_id: chore[:id], roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user))

    deleted = result.value![:deleted]
    types = deleted.map { |d| d[:objectType] }
    expect(types).to include("chore", "choreAssignment")
    expect(deleted.find { |d| d[:objectType] == "chore" }[:id]).to eq(chore[:id].to_s)
    expect(deleted.find { |d| d[:objectType] == "choreAssignment" }[:id]).to eq(assignment[:id].to_s)
  end

  it "returns updated roster in response" do
    result = described_class.call(chore_id: chore[:id], roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user))

    roster_obj = result.value![:objects].find { |o| o[:objectType] == "choreRoster" }
    expect(roster_obj).not_to be_nil
    expect(roster_obj[:choreIds]).not_to include(chore[:id].to_s)
  end

  it "fails for nonexistent chore" do
    result = described_class.call(chore_id: SecureRandom.uuid, roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user))

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
  end

  it "fails when chore belongs to a different roster" do
    other_event = TestFactories.event(workspace: workspace, user: user)
    other_roster = TestFactories.chore_roster(event: other_event, user: user)
    other_chore = TestFactories.chore(chore_roster: other_roster, name: "Cleaning")

    result = described_class.call(chore_id: other_chore[:id], roster_id: roster[:id], workspace_id: workspace[:id], membership: membership_for(user))

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
    expect(DB[:chores].where(id: other_chore[:id]).count).to eq(1)
  end
end
