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
    membership_for(assignee)

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

  describe "attendance resolution" do
    it "links the assignment to the assignee's existing attendance (user_id path)" do
      membership_for(assignee)
      attendance = TestFactories.attendance(event: event, user: assignee)

      result = described_class.call(
        roster_id: roster[:id],
        workspace_id: workspace[:id],
        membership: membership_for(user),
        chore_id: chore[:id].to_s,
        user_id: assignee[:id].to_s,
        date: "2026-03-02"
      )

      assignment = result.value![:objects].find { |o| o[:objectType] == "choreAssignment" }
      expect(assignment[:attendanceId]).to eq(attendance[:id].to_s)
      expect(assignment[:userId]).to eq(assignee[:id].to_s)
    end

    it "synthesizes a pending attendance when the assignee has none (user_id path)" do
      membership_for(assignee)

      result = described_class.call(
        roster_id: roster[:id],
        workspace_id: workspace[:id],
        membership: membership_for(user),
        chore_id: chore[:id].to_s,
        user_id: assignee[:id].to_s,
        date: "2026-03-02"
      )

      assignment = result.value![:objects].find { |o| o[:objectType] == "choreAssignment" }
      row = DB[:attendances].where(id: assignment[:attendanceId]).first
      expect(row[:user_id].to_s).to eq(assignee[:id].to_s)
      expect(row[:status]).to eq("pending")
    end

    it "fails when the assignee is not a workspace member (user_id path)" do
      result = described_class.call(
        roster_id: roster[:id],
        workspace_id: workspace[:id],
        membership: membership_for(user),
        chore_id: chore[:id].to_s,
        user_id: assignee[:id].to_s,
        date: "2026-03-02"
      )

      expect(result.failure.message).to eq("User is not a member of this workspace")
    end

    it "accepts attendance_id and mirrors the member's user_id" do
      membership_for(assignee)
      attendance = TestFactories.attendance(event: event, user: assignee)

      result = described_class.call(
        roster_id: roster[:id],
        workspace_id: workspace[:id],
        membership: membership_for(user),
        chore_id: chore[:id].to_s,
        attendance_id: attendance[:id].to_s,
        date: "2026-03-02"
      )

      assignment = result.value![:objects].find { |o| o[:objectType] == "choreAssignment" }
      expect(assignment[:attendanceId]).to eq(attendance[:id].to_s)
      expect(assignment[:userId]).to eq(assignee[:id].to_s)
    end

    it "rejects an attendance from another event" do
      other_event = TestFactories.event(workspace: workspace, user: user)
      attendance = TestFactories.attendance(event: other_event, user: user)

      result = described_class.call(
        roster_id: roster[:id],
        workspace_id: workspace[:id],
        membership: membership_for(user),
        chore_id: chore[:id].to_s,
        attendance_id: attendance[:id].to_s,
        date: "2026-03-02"
      )

      expect(result.failure.message).to eq("Attendance not found on this event")
    end

    it "rejects a guest attendance" do
      guest = TestFactories.guest(workspace: workspace)
      attendance = TestFactories.attendance(event: event, guest: guest, host: user)

      result = described_class.call(
        roster_id: roster[:id],
        workspace_id: workspace[:id],
        membership: membership_for(user),
        chore_id: chore[:id].to_s,
        attendance_id: attendance[:id].to_s,
        date: "2026-03-02"
      )

      expect(result.failure.message).to eq("Guests cannot be assigned chores yet")
    end

    it "requires attendance_id or user_id, but not both" do
      membership = membership_for(user)
      attendance = TestFactories.attendance(event: event, user: user)

      neither = described_class.call(
        roster_id: roster[:id], workspace_id: workspace[:id], membership: membership,
        chore_id: chore[:id].to_s, date: "2026-03-02"
      )
      expect(neither.failure.message).to eq("attendance_id or user_id is required")

      both = described_class.call(
        roster_id: roster[:id], workspace_id: workspace[:id], membership: membership,
        chore_id: chore[:id].to_s, attendance_id: attendance[:id].to_s, user_id: user[:id].to_s, date: "2026-03-02"
      )
      expect(both.failure.message).to eq("attendance_id and user_id are mutually exclusive")
    end
  end

  it "fails when the note is too long" do
    result = described_class.call(
      roster_id: roster[:id],
      workspace_id: workspace[:id],
      membership: membership_for(user),
      chore_id: chore[:id].to_s,
      user_id: assignee[:id].to_s,
      date: "2026-03-02",
      note: "a" * 501
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Note is too long (maximum 500 characters)")
    expect(result.failure.http_status).to eq(400)
  end

  it "schedules a reminder when the chore has a time" do
    allow(Jobs::Queue).to receive(:enqueue)
    membership_for(assignee)
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
    membership_for(assignee)

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
