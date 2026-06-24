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

  describe "editing the time" do
    before { allow(Jobs::Queue).to receive(:enqueue) }

    # A roster on a future event so rescheduled reminders land in the future
    # (and are actually enqueued rather than skipped as past).
    let(:future_event) do
      e = TestFactories.event(workspace: workspace, user: user)
      DB[:events].where(id: e[:id]).update(start_date: Date.new(2099, 5, 1), end_date: Date.new(2099, 5, 7))
      DB[:events].where(id: e[:id]).first
    end
    let(:future_roster) { TestFactories.chore_roster(event: future_event, user: user) }

    it "sets a time on a previously timeless chore" do
      result = described_class.call(chore_id: chore[:id], workspace_id: workspace[:id], membership: membership_for(user), time: "09:00")

      expect(result.success?).to be true
      updated = result.value![:objects].find { |o| o[:objectType] == "chore" }
      expect(updated[:time]).to eq("09:00")
    end

    it "clears the time" do
      timed = TestFactories.chore(chore_roster: roster, name: "Cooking", time: "18:00")

      result = described_class.call(chore_id: timed[:id], workspace_id: workspace[:id], membership: membership_for(user), time: "")

      expect(result.success?).to be true
      updated = result.value![:objects].find { |o| o[:objectType] == "chore" }
      expect(updated[:time]).to be_nil
    end

    it "rejects a malformed time" do
      result = described_class.call(chore_id: chore[:id], workspace_id: workspace[:id], membership: membership_for(user), time: "9am")

      expect(result.failure?).to be true
      expect(result.failure.message).to include("time")
    end

    it "leaves the time untouched and does not reschedule when time is omitted" do
      timed = TestFactories.chore(chore_roster: future_roster, name: "Cooking", time: "18:00")
      TestFactories.chore_assignment(chore: timed, user: user, date: Date.new(2099, 5, 2))

      result = described_class.call(chore_id: timed[:id], workspace_id: workspace[:id], membership: membership_for(user), name: "Renamed")

      expect(result.success?).to be true
      updated = result.value![:objects].find { |o| o[:objectType] == "chore" }
      expect(updated[:time]).to eq("18:00")
      expect(Jobs::Queue).not_to have_received(:enqueue)
    end

    it "reschedules reminders for the chore's future assignments when the time changes" do
      timed = TestFactories.chore(chore_roster: future_roster, name: "Cooking", time: "18:00")
      assignment = TestFactories.chore_assignment(chore: timed, user: user, date: Date.new(2099, 5, 2))

      described_class.call(chore_id: timed[:id], workspace_id: workspace[:id], membership: membership_for(user), time: "09:00")

      expect(Jobs::Queue).to have_received(:enqueue).with(
        job_class: "ChoreRosters::SendReminder::Job",
        args: { chore_assignment_id: assignment[:id].to_s, expected_time: "09:00" },
        scheduled_at: Time.new(2099, 5, 2, 9, 0, 0)
      )
    end

    it "does not reschedule when the submitted time matches the current one" do
      timed = TestFactories.chore(chore_roster: future_roster, name: "Cooking", time: "18:00")
      TestFactories.chore_assignment(chore: timed, user: user, date: Date.new(2099, 5, 2))

      described_class.call(chore_id: timed[:id], workspace_id: workspace[:id], membership: membership_for(user), name: "Renamed", time: "18:00")

      expect(Jobs::Queue).not_to have_received(:enqueue)
    end
  end
end
