# frozen_string_literal: true

require "spec_helper"

RSpec.describe ChoreRosters::SendReminder do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:event) { TestFactories.event(workspace: workspace, user: user, name: "Cabin trip") }
  let(:roster) { TestFactories.chore_roster(event: event, user: user) }
  let(:chore) { TestFactories.chore(chore_roster: roster, name: "Cooking", time: "18:00") }
  let(:assignment) { TestFactories.chore_assignment(chore: chore, user: user, date: Date.new(2026, 7, 1)) }

  describe ".call" do
    it "delivers a chore_reminder in-app notification to the assigned user" do
      described_class.call(chore_assignment_id: assignment[:id])

      row = DB[:notifications].where(user_id: user[:id]).first
      expect(row).not_to be_nil
      expect(row[:kind]).to eq("chore_reminder")
      expect(row[:workspace_id].to_s).to eq(workspace[:id].to_s)
      expect(row[:data]["body"]).to include("Cooking")
      expect(row[:data]["href"]).to include("/events/#{event[:id]}/chores")
    end

    it "no-ops when the assignment no longer exists" do
      described_class.call(chore_assignment_id: SecureRandom.uuid)

      expect(DB[:notifications].count).to eq(0)
    end

    it "no-ops when the chore has no time" do
      timeless = TestFactories.chore(chore_roster: roster, name: "Dishes")
      a = TestFactories.chore_assignment(chore: timeless, user: user, date: Date.new(2026, 7, 1))

      described_class.call(chore_assignment_id: a[:id])

      expect(DB[:notifications].count).to eq(0)
    end
  end

  describe "via the scheduled job" do
    it "delivers the reminder when a due job is drained by the worker" do
      DB[Jobs::Queue::TABLE].insert(
        job_class: "ChoreRosters::SendReminder::Job",
        args: Sequel.pg_jsonb({ chore_assignment_id: assignment[:id] }),
        scheduled_at: Time.now - 1
      )

      Jobs::Worker.drain

      row = DB[:notifications].where(user_id: user[:id]).first
      expect(row).not_to be_nil
      expect(row[:kind]).to eq("chore_reminder")
      expect(DB[Jobs::Queue::TABLE].count).to eq(0)
    end
  end
end
