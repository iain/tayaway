# frozen_string_literal: true

require "spec_helper"

RSpec.describe EventSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "returns an empty array for an empty input" do
      expect(described_class.serialize_batch([], pool: nil)).to eq([])
    end

    it "serializes fields with camelCase keys and iso8601(3) timestamps" do
      event_row = TestFactories.event(workspace: workspace, user: user, name: "Party")
      event = Event.find(event_row[:id])

      result = described_class.serialize_batch([event], pool: nil).first

      expect(result[:id]).to eq(event.id.to_s)
      expect(result[:objectType]).to eq("event")
      expect(result[:name]).to eq("Party")
      expect(result[:workspaceId]).to eq(workspace[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:createdAt]).to match(/\A\d{4}-\d{2}-\d{2}T.*\.\d{3}/)
      expect(result[:updatedAt]).to match(/\A\d{4}-\d{2}-\d{2}T.*\.\d{3}/)
      expect(result[:datePollId]).to be_nil
      expect(result[:rsvpIds]).to eq([])
    end

    it "includes datePollId and rsvpIds when present" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      event = Event.find(event_row[:id])
      poll = TestFactories.date_poll(event: event_row)
      rsvp = TestFactories.rsvp(event: event_row, user: user)

      result = described_class.serialize_batch([event], pool: nil).first

      expect(result[:datePollId]).to eq(poll[:id].to_s)
      expect(result[:rsvpIds]).to include(rsvp[:id].to_s)
    end

    it "batches date poll and rsvp lookups across multiple events" do
      event1_row = TestFactories.event(workspace: workspace, user: user)
      event2_row = TestFactories.event(workspace: workspace, user: user)
      event1 = Event.find(event1_row[:id])
      event2 = Event.find(event2_row[:id])
      poll = TestFactories.date_poll(event: event1_row)

      result = described_class.serialize_batch([event1, event2], pool: nil)

      expect(result[0][:datePollId]).to eq(poll[:id].to_s)
      expect(result[1][:datePollId]).to be_nil
    end
  end

  describe ".policy_context_batch" do
    it "returns has_expenses: false for events with no financial data" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      event = Event.find(event_row[:id])

      context = described_class.policy_context_batch([event])

      expect(context[event.id.to_s]).to eq(has_expenses: false)
    end

    it "returns has_expenses: true when the event has an expense" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      event = Event.find(event_row[:id])
      DB[:expenses].insert(
        id: SecureRandom.uuid, event_id: event_row[:id], user_id: user[:id],
        description: "x", amount: 1.0, start_date: Date.today, end_date: Date.today,
        created_at: Time.now, updated_at: Time.now
      )

      context = described_class.policy_context_batch([event])

      expect(context[event.id.to_s]).to eq(has_expenses: true)
    end

    it "returns has_expenses: true when the event has a settlement" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      event = Event.find(event_row[:id])
      DB[:settlements].insert(
        id: SecureRandom.uuid, event_id: event_row[:id], user_id: user[:id],
        created_at: Time.now, updated_at: Time.now
      )

      context = described_class.policy_context_batch([event])

      expect(context[event.id.to_s]).to eq(has_expenses: true)
    end
  end

  describe ".policy_context" do
    it "returns the same shape as a single-item batch" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      event = Event.find(event_row[:id])

      expect(described_class.policy_context(event)).to eq(has_expenses: false)
    end
  end
end
