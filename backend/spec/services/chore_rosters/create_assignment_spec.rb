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

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  it "creates a pinned assignment" do
    result = described_class.call(
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      membership: membership_for(user),
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

  it "schedules a reminder when the chore has a time" do
    allow(Jobs::Queue).to receive(:enqueue)
    future_event = TestFactories.event(workspace: workspace, user: user)
    DB[:events].where(id: future_event[:id]).update(start_date: Date.new(2099, 5, 1), end_date: Date.new(2099, 5, 7))
    future_roster = TestFactories.chore_roster(event: future_event, user: user)
    timed_chore = TestFactories.chore(chore_roster: future_roster, name: "Cooking", time: "18:00")
    assignment_id = SecureRandom.uuid

    described_class.call(
      roster_id: future_roster[:id],
      workspace_id: workspace[:id],
      membership: membership_for(user),
      chore_id: timed_chore[:id].to_s,
      user_id: assignee[:id].to_s,
      date: "2099-05-02",
      id: assignment_id
    )

    expect(Jobs::Queue).to have_received(:enqueue).with(
      job_class: "ChoreRosters::SendReminder::Job",
      args: { chore_assignment_id: assignment_id, expected_time: "18:00" },
      scheduled_at: Timezones.resolve(date: Date.new(2099, 5, 2), hour: 18, min: 0, zone: "Europe/Amsterdam")
    )
  end

  it "does not schedule a reminder for a timeless chore" do
    allow(Jobs::Queue).to receive(:enqueue)

    described_class.call(
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      membership: membership_for(user),
      chore_id: chore[:id].to_s,
      user_id: assignee[:id].to_s,
      date: "2026-03-02"
    )

    expect(Jobs::Queue).not_to have_received(:enqueue)
  end

  it "fails when date is outside event range" do
    result = described_class.call(
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      membership: membership_for(user),
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
      membership: membership_for(user),
      chore_id: other_chore[:id].to_s,
      user_id: assignee[:id].to_s,
      date: "2026-03-02"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to include("not found")
  end
end
