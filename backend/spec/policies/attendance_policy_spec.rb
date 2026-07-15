# frozen_string_literal: true

require "spec_helper"

RSpec.describe AttendancePolicy do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:membership) { WorkspaceMembership.find(TestFactories.workspace_membership(workspace: workspace, user: user)[:id]) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: user) }

  def member_attendance
    Attendance.find(TestFactories.attendance(event: event_row, user: user)[:id])
  end

  def guest_attendance
    guest = TestFactories.guest(workspace: workspace)
    Attendance.find(TestFactories.attendance(event: event_row, guest: guest, host: user)[:id])
  end

  it "lets any workspace member edit any attendance" do
    policy = described_class.new(member_attendance, membership: membership)
    expect(policy.edit).to be_success
  end

  it "lets a member decline when nothing blocks it" do
    policy = described_class.new(member_attendance, membership: membership)
    expect(policy.decline).to be_success
  end

  it "blocks a member decline while the subject has expenses on the event" do
    policy = described_class.new(member_attendance, membership: membership, has_expenses: true)
    expect(policy.decline).to be_failure
    expect(policy.decline.failure).to eq(:has_expenses)
  end

  it "blocks a member decline while the subject hosts going guests on the event" do
    policy = described_class.new(member_attendance, membership: membership, has_going_guests: true)
    expect(policy.decline).to be_failure
    expect(policy.decline.failure).to eq(:has_going_guests)
  end

  it "always allows declining a guest row — removal is the same verb" do
    policy = described_class.new(guest_attendance, membership: membership, has_expenses: true, has_going_guests: true)
    expect(policy.decline).to be_success
  end

  it "has correct ACTIONS" do
    expect(described_class::ACTIONS).to contain_exactly(:edit, :decline)
  end
end
