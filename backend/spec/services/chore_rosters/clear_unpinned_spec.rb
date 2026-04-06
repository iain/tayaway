# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::ClearUnpinned do
  it "returns failure when roster not found" do
    result = described_class.call(roster_id: SecureRandom.uuid, workspace_id: SecureRandom.uuid)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Chore roster not found")
  end

  it "deletes non-pinned assignments while preserving pinned ones" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    roster = TestFactories.chore_roster(event: event, user: user)
    chore = TestFactories.chore(chore_roster: roster)

    pinned = TestFactories.chore_assignment(chore: chore, user: user, date: Date.today, pinned: true)
    unpinned1 = TestFactories.chore_assignment(chore: chore, user: user, date: Date.today + 1, pinned: false)
    unpinned2 = TestFactories.chore_assignment(chore: chore, user: user, date: Date.today + 2, pinned: false)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id])

    expect(result.success?).to be true
    expect(result.value![:deleted].map { |d| d[:id] }).to contain_exactly(unpinned1[:id], unpinned2[:id])
    expect(DB[:chore_assignments].where(id: pinned[:id]).count).to eq(1)
    expect(DB[:chore_assignments].where(id: unpinned1[:id]).count).to eq(0)
    expect(DB[:chore_assignments].where(id: unpinned2[:id]).count).to eq(0)
  end

  it "does nothing when no non-pinned assignments exist" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    roster = TestFactories.chore_roster(event: event, user: user)
    chore = TestFactories.chore(chore_roster: roster)

    TestFactories.chore_assignment(chore: chore, user: user, date: Date.today, pinned: true)

    allow(Broadcaster).to receive(:object_changed)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id])

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([])
    expect(DB[:chore_assignments].count).to eq(1)
    expect(Broadcaster).not_to have_received(:object_changed)
  end

  it "does not broadcast when roster has no assignments at all" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    roster = TestFactories.chore_roster(event: event, user: user)

    allow(Broadcaster).to receive(:object_changed)

    result = described_class.call(roster_id: roster[:id], workspace_id: workspace[:id])

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([])
    expect(Broadcaster).not_to have_received(:object_changed)
  end

  it "inserts deleted_items records for cleared assignments" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    roster = TestFactories.chore_roster(event: event, user: user)
    chore = TestFactories.chore(chore_roster: roster)

    assignment = TestFactories.chore_assignment(chore: chore, user: user, date: Date.today, pinned: false)

    described_class.call(roster_id: roster[:id], workspace_id: workspace[:id])

    expect(DB[:deleted_items].where(object_type: "chore_assignment", object_id: assignment[:id]).count).to eq(1)
  end

  it "sends one deletion broadcast per deleted assignment and one roster-level change" do
    workspace = TestFactories.workspace
    user = TestFactories.user
    event = TestFactories.event(workspace: workspace, user: user)
    roster = TestFactories.chore_roster(event: event, user: user)
    chore = TestFactories.chore(chore_roster: roster)

    assignments = Array.new(3) do |i|
      TestFactories.chore_assignment(chore: chore, user: user, date: Date.today + i, pinned: false)
    end

    allow(Broadcaster).to receive(:object_deleted)
    allow(Broadcaster).to receive(:object_changed)

    described_class.call(roster_id: roster[:id], workspace_id: workspace[:id])

    assignments.each do |a|
      expect(Broadcaster).to have_received(:object_deleted)
        .with("chore_assignment", a[:id], workspace_id: workspace[:id])
    end
    expect(Broadcaster).to have_received(:object_changed)
      .with("chore_roster", anything, workspace_id: workspace[:id]).once
    expect(Broadcaster).to have_received(:object_changed).once
  end
end
