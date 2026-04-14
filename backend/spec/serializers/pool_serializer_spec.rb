# frozen_string_literal: true

require "spec_helper"

RSpec.describe PoolSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe "#add" do
    it "serializes multiple events without N+1 date poll queries" do
      event1 = TestFactories.event(workspace: workspace, user: user, name: "Event 1")
      event2 = TestFactories.event(workspace: workspace, user: user, name: "Event 2")
      poll = TestFactories.date_poll(event: event1)
      rsvp = TestFactories.rsvp(event: event1, user: user)

      pool = described_class.new(workspace_id: workspace[:id])
      events = Event.for_workspace(workspace[:id])

      pool.add(:event, events)

      objects = pool.to_a
      types = objects.map { |o| o[:objectType] }
      expect(types).to include("event").twice

      event1_obj = objects.find { |o| o[:objectType] == "event" && o[:id] == event1[:id].to_s }
      event2_obj = objects.find { |o| o[:objectType] == "event" && o[:id] == event2[:id].to_s }

      expect(event1_obj[:datePollId]).to eq(poll[:id].to_s)
      expect(event1_obj[:rsvpIds]).to include(rsvp[:id].to_s)

      expect(event2_obj[:datePollId]).to be_nil
      expect(event2_obj[:rsvpIds]).to eq([])
    end

    it "skips events already in the pool" do
      event = TestFactories.event(workspace: workspace, user: user)
      event_model = Event.find(event[:id])

      pool = described_class.new(workspace_id: workspace[:id])
      pool.add(:event, [event_model])
      pool.add(:event, [event_model])

      expect(pool.to_a.count { |o| o[:objectType] == "event" }).to eq(1)
    end

    it "raises on an unknown object key" do
      pool = described_class.new(workspace_id: workspace[:id])

      expect { pool.add(:nope, []) }.to raise_error(ArgumentError, /Unknown object key/)
    end

    it "raises if a serializer returns fewer hashes than items" do
      event1 = TestFactories.event(workspace: workspace, user: user)
      event2 = TestFactories.event(workspace: workspace, user: user)
      events = [Event.find(event1[:id]), Event.find(event2[:id])]
      allow(EventSerializer).to receive(:serialize_batch).and_return([{ id: events.first.id.to_s, objectType: "event" }])

      pool = described_class.new(workspace_id: workspace[:id])

      expect { pool.add(:event, events) }.to raise_error(/returned 1 hashes for 2 items/)
    end
  end

  describe "#add date_polls" do
    it "serializes multiple date polls without N+1 date range queries" do
      event1 = TestFactories.event(workspace: workspace, user: user)
      event2 = TestFactories.event(workspace: workspace, user: user)
      poll1 = TestFactories.date_poll(event: event1)
      poll2 = TestFactories.date_poll(event: event2)
      range = TestFactories.date_range(date_poll: poll1)

      pool = described_class.new(workspace_id: workspace[:id])
      polls = [DatePoll.find(poll1[:id]), DatePoll.find(poll2[:id])]

      pool.add(:date_poll, polls)

      objects = pool.to_a
      poll1_obj = objects.find { |o| o[:objectType] == "datePoll" && o[:id] == poll1[:id].to_s }
      poll2_obj = objects.find { |o| o[:objectType] == "datePoll" && o[:id] == poll2[:id].to_s }

      expect(poll1_obj[:dateRangeIds]).to include(range[:id].to_s)
      expect(poll2_obj[:dateRangeIds]).to eq([])
    end
  end

  describe "#add date_ranges" do
    it "serializes multiple date ranges in a single batch" do
      event = TestFactories.event(workspace: workspace, user: user)
      poll = TestFactories.date_poll(event: event)
      range1 = TestFactories.date_range(date_poll: poll, start_date: Date.today, end_date: Date.today + 3)
      range2 = TestFactories.date_range(date_poll: poll, start_date: Date.today + 7, end_date: Date.today + 10)

      pool = described_class.new(workspace_id: workspace[:id])
      ranges = [DateRange.find(range1[:id]), DateRange.find(range2[:id])]

      pool.add(:date_range, ranges)

      objects = pool.to_a
      range1_obj = objects.find { |o| o[:objectType] == "dateRange" && o[:id] == range1[:id].to_s }
      range2_obj = objects.find { |o| o[:objectType] == "dateRange" && o[:id] == range2[:id].to_s }

      expect(range1_obj[:objectType]).to eq("dateRange")
      expect(range1_obj[:datePollId]).to eq(poll[:id].to_s)
      expect(range2_obj[:datePollId]).to eq(poll[:id].to_s)
      expect(range1_obj).not_to have_key(:voteIds)
      expect(range2_obj).not_to have_key(:voteIds)
    end
  end

  describe "#add settlements" do
    it "serializes multiple settlements without N+1 transfer queries" do
      event = TestFactories.event(workspace: workspace, user: user)
      user2 = TestFactories.user
      settlement1_id = SecureRandom.uuid
      DB[:settlements].insert(id: settlement1_id, event_id: event[:id], user_id: user[:id], created_at: Time.now, updated_at: Time.now)
      settlement2_id = SecureRandom.uuid
      DB[:settlements].insert(id: settlement2_id, event_id: event[:id], user_id: user2[:id], created_at: Time.now, updated_at: Time.now)

      transfer_id = SecureRandom.uuid
      DB[:settlement_transfers].insert(
        id: transfer_id,
        settlement_id: settlement1_id,
        from_user_id: user2[:id],
        to_user_id: user[:id],
        amount: 10.0,
        created_at: Time.now,
        updated_at: Time.now
      )

      pool = described_class.new(workspace_id: workspace[:id])
      settlements = [Settlement.find(settlement1_id), Settlement.find(settlement2_id)]

      pool.add(:settlement, settlements)

      objects = pool.to_a
      s1_obj = objects.find { |o| o[:objectType] == "settlement" && o[:id] == settlement1_id.to_s }
      s2_obj = objects.find { |o| o[:objectType] == "settlement" && o[:id] == settlement2_id.to_s }

      expect(s1_obj[:transferIds]).to include(transfer_id.to_s)
      expect(s2_obj[:transferIds]).to eq([])
    end
  end
end
