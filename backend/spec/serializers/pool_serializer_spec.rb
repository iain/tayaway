# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe PoolSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe "#add_events_batch" do
    it "serializes multiple events without N+1 date poll queries" do
      event1 = TestFactories.event(workspace: workspace, user: user, name: "Event 1")
      event2 = TestFactories.event(workspace: workspace, user: user, name: "Event 2")
      poll = TestFactories.date_poll(event: event1)
      rsvp = TestFactories.rsvp(event: event1, user: user)

      pool = described_class.new(workspace_id: workspace[:id])
      events = Event.for_workspace(workspace[:id])

      pool.add_events_batch(events)

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
      pool.add_event(event_model)
      pool.add_events_batch([event_model])

      expect(pool.to_a.count { |o| o[:objectType] == "event" }).to eq(1)
    end
  end

  describe "#add_date_polls_batch" do
    it "serializes multiple date polls without N+1 date range queries" do
      event1 = TestFactories.event(workspace: workspace, user: user)
      event2 = TestFactories.event(workspace: workspace, user: user)
      poll1 = TestFactories.date_poll(event: event1)
      poll2 = TestFactories.date_poll(event: event2)
      range = TestFactories.date_range(date_poll: poll1)

      pool = described_class.new(workspace_id: workspace[:id])
      polls = [DatePoll.find(poll1[:id]), DatePoll.find(poll2[:id])]

      pool.add_date_polls_batch(polls)

      objects = pool.to_a
      poll1_obj = objects.find { |o| o[:objectType] == "datePoll" && o[:id] == poll1[:id].to_s }
      poll2_obj = objects.find { |o| o[:objectType] == "datePoll" && o[:id] == poll2[:id].to_s }

      expect(poll1_obj[:dateRangeIds]).to include(range[:id].to_s)
      expect(poll2_obj[:dateRangeIds]).to eq([])
    end
  end

  describe "#add_date_ranges_batch" do
    it "serializes multiple date ranges without N+1 vote queries" do
      event = TestFactories.event(workspace: workspace, user: user)
      poll = TestFactories.date_poll(event: event)
      range1 = TestFactories.date_range(date_poll: poll, start_date: Date.today, end_date: Date.today + 3)
      range2 = TestFactories.date_range(date_poll: poll, start_date: Date.today + 7, end_date: Date.today + 10)
      vote = TestFactories.vote(date_range: range1, user: user)

      pool = described_class.new(workspace_id: workspace[:id])
      ranges = [DateRange.find(range1[:id]), DateRange.find(range2[:id])]

      pool.add_date_ranges_batch(ranges)

      objects = pool.to_a
      range1_obj = objects.find { |o| o[:objectType] == "dateRange" && o[:id] == range1[:id].to_s }
      range2_obj = objects.find { |o| o[:objectType] == "dateRange" && o[:id] == range2[:id].to_s }

      expect(range1_obj[:voteIds]).to include(vote[:id].to_s)
      expect(range2_obj[:voteIds]).to eq([])
    end
  end

  describe "#add_settlements_batch" do
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

      pool.add_settlements_batch(settlements)

      objects = pool.to_a
      s1_obj = objects.find { |o| o[:objectType] == "settlement" && o[:id] == settlement1_id.to_s }
      s2_obj = objects.find { |o| o[:objectType] == "settlement" && o[:id] == settlement2_id.to_s }

      expect(s1_obj[:transferIds]).to include(transfer_id.to_s)
      expect(s2_obj[:transferIds]).to eq([])
    end
  end
end
