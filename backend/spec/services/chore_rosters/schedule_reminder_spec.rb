# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::ScheduleReminder do
  let(:user) { TestFactories.user }
  let(:roster) { TestFactories.chore_roster(user: user) }

  before { allow(Jobs::Queue).to receive(:enqueue) }

  def assignment_for(chore, date)
    ChoreAssignment.find(TestFactories.chore_assignment(chore: chore, user: user, date: date)[:id])
  end

  it "enqueues a reminder at the chore's time, read in the given zone" do
    chore = TestFactories.chore(chore_roster: roster, time: "07:30")
    assignment = assignment_for(chore, Date.new(2099, 5, 4))

    described_class.call(assignment: assignment, timezone: "Europe/Amsterdam")

    expect(Jobs::Queue).to have_received(:enqueue).with(
      job_class: "ChoreRosters::SendReminder::Job",
      args: { chore_assignment_id: assignment.id.to_s, expected_time: "07:30" },
      # The instant is the chore's wall-clock time read in the event's zone —
      # whatever offset that zone has on the date.
      scheduled_at: Timezones.resolve(date: Date.new(2099, 5, 4), hour: 7, min: 30, zone: "Europe/Amsterdam")
    )
  end

  it "reads the same wall-clock time differently in another zone" do
    chore = TestFactories.chore(chore_roster: roster, time: "07:30")
    assignment = assignment_for(chore, Date.new(2099, 5, 4))

    described_class.call(assignment: assignment, timezone: "America/New_York")

    ny = Timezones.resolve(date: Date.new(2099, 5, 4), hour: 7, min: 30, zone: "America/New_York")
    ams = Timezones.resolve(date: Date.new(2099, 5, 4), hour: 7, min: 30, zone: "Europe/Amsterdam")
    expect(Jobs::Queue).to have_received(:enqueue).with(hash_including(scheduled_at: ny))
    expect(ny).not_to eq(ams)
  end

  it "does not enqueue when the chore has no time" do
    chore = TestFactories.chore(chore_roster: roster)
    assignment = assignment_for(chore, Date.new(2099, 5, 4))

    described_class.call(assignment: assignment, timezone: "Europe/Amsterdam")

    expect(Jobs::Queue).not_to have_received(:enqueue)
  end

  it "does not enqueue when the reminder time is already in the past" do
    chore = TestFactories.chore(chore_roster: roster, time: "07:30")
    assignment = assignment_for(chore, Date.new(2000, 1, 1))

    described_class.call(assignment: assignment, timezone: "Europe/Amsterdam")

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
