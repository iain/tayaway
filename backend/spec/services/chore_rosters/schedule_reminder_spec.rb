# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::ScheduleReminder do
  let(:user) { TestFactories.user }
  let(:roster) { TestFactories.chore_roster(user: user) }

  before { allow(Jobs::Queue).to receive(:enqueue) }

  def assignment_for(chore, date)
    ChoreAssignment.find(TestFactories.chore_assignment(chore: chore, user: user, date: date)[:id])
  end

  it "enqueues a reminder job at the chore's time on the assignment date" do
    chore = TestFactories.chore(chore_roster: roster, time: "07:30")
    assignment = assignment_for(chore, Date.new(2099, 5, 4))

    described_class.call(assignment: assignment)

    expect(Jobs::Queue).to have_received(:enqueue).with(
      job_class: "ChoreRosters::SendReminder::Job",
      args: { chore_assignment_id: assignment.id.to_s, expected_time: "07:30" },
      scheduled_at: Time.new(2099, 5, 4, 7, 30, 0)
    )
  end

  it "does not enqueue when the chore has no time" do
    chore = TestFactories.chore(chore_roster: roster)
    assignment = assignment_for(chore, Date.new(2099, 5, 4))

    described_class.call(assignment: assignment)

    expect(Jobs::Queue).not_to have_received(:enqueue)
  end

  it "does not enqueue when the reminder time is already in the past" do
    chore = TestFactories.chore(chore_roster: roster, time: "07:30")
    assignment = assignment_for(chore, Date.new(2000, 1, 1))

    described_class.call(assignment: assignment)

    expect(Jobs::Queue).not_to have_received(:enqueue)
  end
end
