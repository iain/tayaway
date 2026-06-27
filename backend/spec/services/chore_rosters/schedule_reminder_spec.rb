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

  describe ".cancel" do
    let(:chore) { TestFactories.chore(chore_roster: roster, time: "07:30") }
    let(:assignment) { assignment_for(chore, Date.new(2099, 5, 4)) }

    def queue_reminder(for_assignment, locked_at: nil)
      DB[Jobs::Queue::TABLE].insert(
        job_class: "ChoreRosters::SendReminder::Job",
        args: Sequel.pg_jsonb({ chore_assignment_id: for_assignment.id.to_s, expected_time: "07:30" }),
        scheduled_at: Time.new(2099, 5, 4, 7, 30, 0),
        locked_at: locked_at
      )
    end

    def reminder_jobs
      DB[Jobs::Queue::TABLE].where(job_class: "ChoreRosters::SendReminder::Job")
    end

    it "deletes a pending reminder job for the assignment" do
      queue_reminder(assignment)

      described_class.cancel(assignment: assignment)

      expect(reminder_jobs.count).to eq(0)
    end

    it "leaves an in-flight (locked) job alone" do
      queue_reminder(assignment, locked_at: Time.now)

      described_class.cancel(assignment: assignment)

      expect(reminder_jobs.count).to eq(1)
    end

    it "leaves another assignment's reminder alone" do
      other = assignment_for(chore, Date.new(2099, 5, 5))
      queue_reminder(other)

      described_class.cancel(assignment: assignment)

      expect(reminder_jobs.count).to eq(1)
    end
  end
end
