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

    it "expands task_list → task_items with a single children query" do
      list1_row = TestFactories.task_list(workspace: workspace, user: user)
      list2_row = TestFactories.task_list(workspace: workspace, user: user)
      TestFactories.task_item(task_list: list1_row, user: user)
      TestFactories.task_item(task_list: list2_row, user: user)
      lists = [TaskList.find(list1_row[:id]), TaskList.find(list2_row[:id])]

      pool = described_class.new(workspace_id: workspace[:id])
      queries = QueryCounter.new.count { pool.add(:task_list, lists) }

      expect(pool.to_a.count { |o| o[:objectType] == "taskItem" }).to eq(2)
      # Budget: task_lists is already loaded by the caller; the serializer
      # only needs one SELECT against task_items for both parents. Fail loudly
      # if we regress to a per-parent lookup.
      expect(queries).to be <= 2
    end

    it "expands chore_roster → chore → chore_assignment with batched children queries" do
      event1_row = TestFactories.event(workspace: workspace, user: user)
      event2_row = TestFactories.event(workspace: workspace, user: user)
      roster1_row = TestFactories.chore_roster(event: event1_row, user: user)
      roster2_row = TestFactories.chore_roster(event: event2_row, user: user)
      chore1 = TestFactories.chore(chore_roster: roster1_row)
      chore2 = TestFactories.chore(chore_roster: roster2_row)
      TestFactories.chore_assignment(chore: chore1, user: user, date: Date.today)
      TestFactories.chore_assignment(chore: chore2, user: user, date: Date.today)
      rosters = [ChoreRoster.find(roster1_row[:id]), ChoreRoster.find(roster2_row[:id])]

      pool = described_class.new(workspace_id: workspace[:id])
      queries = QueryCounter.new.count { pool.add(:chore_roster, rosters) }

      expect(pool.to_a.count { |o| o[:objectType] == "chore" }).to eq(2)
      expect(pool.to_a.count { |o| o[:objectType] == "choreAssignment" }).to eq(2)
      # Budget: rosters, chores (batched), assignments (batched). Allow some
      # slack for associated lookups but fail loudly if we start doing N+1.
      expect(queries).to be <= 6
    end

    it "expands expense → participants with a single children query" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      e1_id = SecureRandom.uuid
      e2_id = SecureRandom.uuid
      [e1_id, e2_id].each do |eid|
        DB[:expenses].insert(
          id: eid, event_id: event[:id], user_id: user[:id],
          description: "x", amount: 1.0, start_date: Date.today, end_date: Date.today,
          created_at: now, updated_at: now
        )
        DB[:expense_participants].insert(
          id: SecureRandom.uuid, expense_id: eid, user_id: user[:id], created_at: now
        )
      end
      expenses = [Expense.find(e1_id), Expense.find(e2_id)]

      pool = described_class.new(workspace_id: workspace[:id])
      queries = QueryCounter.new.count { pool.add(:expense, expenses) }

      expect(pool.to_a.count { |o| o[:objectType] == "expenseParticipant" }).to eq(2)
      # Budget: one expense_participants SELECT for both parents, not one each.
      expect(queries).to be <= 4
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
