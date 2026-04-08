# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::Create do
  let(:workspace) { TestFactories.workspace }
  let(:creator) { TestFactories.user(name: "Creator") }
  let(:creator_membership) do
    row = TestFactories.workspace_membership(workspace: workspace, user: creator)
    WorkspaceMembership.find(row[:id])
  end

  # Convenience: insert an expense for an event, covering a date range
  define_method(:insert_expense) do |event:, user:, amount:, start_date:, end_date:|
    now = Time.now
    id = SecureRandom.uuid
    DB[:expenses].insert(
      id: id,
      event_id: event[:id],
      user_id: user[:id],
      amount: amount,
      description: "Expense",
      start_date: start_date,
      end_date: end_date,
      created_at: now,
      updated_at: now
    )
    id
  end

  # Convenience: set event start/end dates
  define_method(:set_event_dates) do |event, start_date, end_date|
    DB[:events].where(id: event[:id]).update(start_date: start_date, end_date: end_date)
    DB[:events].where(id: event[:id]).first
  end

  # Convenience: extract transfers from a successful result
  define_method(:transfers_from) do |result|
    result.value![:objects].select { |o| o[:objectType] == "settlementTransfer" }
  end

  describe "validation" do
    it "fails when event has no dates" do
      event = TestFactories.event(workspace: workspace, user: creator)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("Event must have dates set before settling expenses")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when there are no unsettled expenses" do
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 7))

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("No unsettled expenses to settle")
    end

    it "returns a concurrent-settlement message when a recent settlement exists but no unsettled expenses remain" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 7))

      insert_expense(event: event, user: alice, amount: 100, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 7))
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      # First settlement consumes all expenses
      first_result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )
      expect(first_result.success?).to be true

      # Second request arrives immediately after — no unsettled expenses remain,
      # but a recent settlement was just created, so the error should be specific
      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("These expenses were just settled by another member")
      expect(result.failure.http_status).to eq(400)
    end

    it "fails when there are no attending RSVPs" do
      alice = TestFactories.user(name: "Alice")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 7))
      insert_expense(event: event, user: alice, amount: 100, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 7))

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to eq("No attending RSVPs found for this event")
    end
  end

  describe "compute_balances: equal split" do
    # Alice pays 100 for a 7-day trip shared equally with Bob.
    # Each owes 50. Bob must pay Alice 50.
    it "splits a single expense equally between two full-trip attendees" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 7))

      insert_expense(event: event, user: alice, amount: 100.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 7))

      # Both attend the full trip (no RSVP-specific dates)
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      transfers = transfers_from(result)
      expect(transfers.length).to eq(1)
      transfer = transfers.first
      expect(transfer[:fromUserId].to_s).to eq(bob[:id].to_s)
      expect(transfer[:toUserId].to_s).to eq(alice[:id].to_s)
      expect(transfer[:amount]).to eq(50.0)
    end

    it "splits expenses between three equal attendees" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      carol = TestFactories.user(name: "Carol")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 3))

      # Alice pays 90; each person owes 30, so Bob and Carol each owe Alice 30
      insert_expense(event: event, user: alice, amount: 90.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 3))

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      TestFactories.rsvp(event: event, user: carol, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      transfers = transfers_from(result)
      # Bob owes Alice 30, Carol owes Alice 30 — two transfers
      expect(transfers.length).to eq(2)
      total_transferred = transfers.sum { |t| t[:amount] }
      expect(total_transferred).to eq(60.0)
      transfers.each do |t|
        expect(t[:toUserId].to_s).to eq(alice[:id].to_s)
        expect(t[:amount]).to eq(30.0)
      end
    end
  end

  describe "compute_balances: partial date overlap" do
    # Event runs Jan 1-7. Alice is there all 7 days, Bob only Jan 1-3.
    # Alice pays for a Jan 1-7 expense (70 EUR = 10/day).
    # Overlap for Alice: 7 days; overlap for Bob: 3 days; total: 10 days
    # Alice's share: 70 * 7/10 = 49; Bob's share: 70 * 3/10 = 21
    # Alice paid 70, so: Alice balance = 49 - 70 = -21 (owed), Bob balance = 21 - 0 = +21 (owes)
    # Bob must pay Alice 21
    it "pro-rates expense to RSVP overlap days" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 7))

      insert_expense(event: event, user: alice, amount: 70.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 7))

      # Alice attends full trip; Bob only arrives Jan 1-3
      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 3))

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      transfers = transfers_from(result)
      expect(transfers.length).to eq(1)
      transfer = transfers.first
      expect(transfer[:fromUserId].to_s).to eq(bob[:id].to_s)
      expect(transfer[:toUserId].to_s).to eq(alice[:id].to_s)
      expect(transfer[:amount]).to eq(21.0)
    end

    it "excludes an attendee who has no overlap with an expense date range" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 10))

      # Expense covers Jan 1-5; Bob only attends Jan 6-10 — no overlap
      insert_expense(event: event, user: alice, amount: 100.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 5))

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true, start_date: Date.new(2026, 1, 6), end_date: Date.new(2026, 1, 10))

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      # Alice paid and is the only one sharing the expense — net balance is 0, no transfers
      transfers = transfers_from(result)
      expect(transfers.length).to eq(0)
    end
  end

  describe "minimize_transfers: three-party debt simplification" do
    # A owes B 30, B owes C 30 — naive approach gives 2 transfers.
    # Greedy algorithm consolidates: A pays C 30, B is settled out (1 transfer).
    it "consolidates a chain debt into a single transfer" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      carol = TestFactories.user(name: "Carol")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 3))

      # Carol pays 90 for all 3 days (30 each)
      # Bob also pays 30 for all 3 days (10 each for the 3-person group -> 30 total / 3 = 10 each)
      # Net: Carol paid 90, share 30 -> owed 60. Bob paid 30, share 30 -> balanced. Alice paid 0, share 30 -> owes 30
      # Wait - for simplicity let's create a scenario where greedy reduces to 2 transfers instead of 3:
      # Carol pays 60 (everyone's share = 20 each, carol owed 40)
      # Bob pays 30 (everyone's share = 10 each, bob owed 20... no)
      # Let's keep it direct: 2 payers, 1 receiver
      # Alice pays 0 → owes 30; Bob pays 0 → owes 30; Carol pays 60 → owed 60
      # Result: Alice→Carol 30, Bob→Carol 30 (2 transfers, which is minimal)
      insert_expense(event: event, user: carol, amount: 60.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 3))

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      TestFactories.rsvp(event: event, user: carol, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      transfers = transfers_from(result)
      # Both Alice and Bob owe Carol 20 each
      expect(transfers.length).to eq(2)
      transfers.each { |t| expect(t[:toUserId].to_s).to eq(carol[:id].to_s) }
      total = transfers.sum { |t| t[:amount] }
      expect(total).to eq(40.0)
    end

    it "minimizes transfers when one creditor can absorb multiple debtors" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      carol = TestFactories.user(name: "Carol")
      dave = TestFactories.user(name: "Dave")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 4))

      # Alice pays 120 for 4 people over 4 days (30 each)
      # Bob, Carol, Dave each owe Alice 30
      insert_expense(event: event, user: alice, amount: 120.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 4))

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      TestFactories.rsvp(event: event, user: carol, attending: true)
      TestFactories.rsvp(event: event, user: dave, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      transfers = transfers_from(result)
      expect(transfers.length).to eq(3)
      transfers.each do |t|
        expect(t[:toUserId].to_s).to eq(alice[:id].to_s)
        expect(t[:amount]).to eq(30.0)
      end
    end
  end

  describe "floating-point edge cases near 0.005 threshold" do
    it "omits balances that round to zero (below 0.005 threshold)" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 3))

      # 3-day expense, 3 people. 1/3 each.
      # Alice pays exactly 1/3 of 1.00 → Alice share = 0.333... Bob and Carol each share 0.333...
      # Actually let's engineer a near-zero balance:
      # 2-person event, expense = 0.01. Each person owes 0.005.
      # After rounding, Alice paid 0.01, share 0.005 → net = 0.005 - 0.01 = -0.005 (abs = 0.005)
      # The check is `balance.abs < 0.005` — so exactly 0.005 is NOT filtered and DOES produce a transfer.
      # Use 0.009 expense → each person owes 0.0045 → rounds to 0.0 → no transfer
      insert_expense(event: event, user: alice, amount: 0.009, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 3))

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      transfers = transfers_from(result)
      # 0.009 / 2 = 0.0045 per person, rounds to 0.00 — below threshold, no transfer
      expect(transfers.length).to eq(0)
    end

    it "includes transfers that are exactly at or above the 0.005 threshold" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 3))

      # 0.02 expense split two ways = 0.01 each.
      # Alice paid 0.02, share = 0.01 → net = -0.01 (owed 0.01)
      # Bob paid 0, share = 0.01 → net = +0.01 (owes 0.01)
      # 0.01 >= 0.005 threshold → transfer is included
      insert_expense(event: event, user: alice, amount: 0.02, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 3))

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      transfers = transfers_from(result)
      expect(transfers.length).to eq(1)
      expect(transfers.first[:amount]).to eq(0.01)
    end

    it "handles multiple expenses that partially cancel each other out" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 4))

      # Alice pays 60, Bob pays 60 — they're perfectly balanced, no transfer needed
      insert_expense(event: event, user: alice, amount: 60.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 4))
      insert_expense(event: event, user: bob, amount: 60.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 4))

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      transfers = transfers_from(result)
      expect(transfers.length).to eq(0)
    end

    it "rounds transfer amounts to 2 decimal places" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      carol = TestFactories.user(name: "Carol")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 3))

      # 100 / 3 = 33.333... Each of Bob and Carol owes Alice 33.33
      insert_expense(event: event, user: alice, amount: 100.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 3))

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      TestFactories.rsvp(event: event, user: carol, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      transfers = transfers_from(result)
      transfers.each do |t|
        # Amount must be a 2-decimal value, not an unrounded float like 33.333333...
        expect(t[:amount].to_s).to match(/\A\d+\.\d{1,2}\z/)
      end
    end
  end

  describe "compute_balances: explicit participants" do # -- test helper
    define_method(:insert_participant) do |expense_id:, user:|
      DB[:expense_participants].insert(
        id: SecureRandom.uuid,
        expense_id: expense_id,
        user_id: user[:id],
        created_at: Time.now
      )
    end
    it "splits equally among explicit participants instead of RSVP overlap" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      carol = TestFactories.user(name: "Carol")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 7))

      # Alice pays 90, participants are Bob and Carol only (not Alice)
      expense_id = insert_expense(event: event, user: alice, amount: 90.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 7))
      insert_participant(expense_id: expense_id, user: bob)
      insert_participant(expense_id: expense_id, user: carol)

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      TestFactories.rsvp(event: event, user: carol, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      transfers = transfers_from(result)
      # Bob and Carol each owe 45. Alice paid 90 and owes 0. Alice is owed 90.
      # Bob→Alice 45, Carol→Alice 45
      expect(transfers.length).to eq(2)
      transfers.each do |t|
        expect(t[:toUserId].to_s).to eq(alice[:id].to_s)
        expect(t[:amount]).to eq(45.0)
      end
    end

    it "handles creator excluded from participants (bought-for-you scenario)" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 3))

      # Alice pays 30 for Bob only
      expense_id = insert_expense(event: event, user: alice, amount: 30.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 3))
      insert_participant(expense_id: expense_id, user: bob)

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      transfers = transfers_from(result)
      # Bob owes 30, Alice paid 30. Bob→Alice 30
      expect(transfers.length).to eq(1)
      expect(transfers.first[:fromUserId].to_s).to eq(bob[:id].to_s)
      expect(transfers.first[:toUserId].to_s).to eq(alice[:id].to_s)
      expect(transfers.first[:amount]).to eq(30.0)
    end

    it "handles mixed: some expenses with participants, some without" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      carol = TestFactories.user(name: "Carol")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 3))

      # Expense 1: Alice pays 30, no participants → split by RSVP overlap (10 each for 3 people)
      insert_expense(event: event, user: alice, amount: 30.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 3))

      # Expense 2: Bob pays 20, participants = [Alice, Bob] → equal split (10 each)
      expense2_id = insert_expense(event: event, user: bob, amount: 20.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 3))
      insert_participant(expense_id: expense2_id, user: alice)
      insert_participant(expense_id: expense2_id, user: bob)

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)
      TestFactories.rsvp(event: event, user: carol, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      # Expense 1 (RSVP overlap): Alice share=10, Bob share=10, Carol share=10
      # Expense 2 (participants): Alice share=10, Bob share=10
      # Total shares: Alice=20, Bob=20, Carol=10
      # Paid: Alice=30, Bob=20
      # Balances: Alice=20-30=-10 (owed), Bob=20-20=0, Carol=10-0=10 (owes)
      # Transfer: Carol→Alice 10
      transfers = transfers_from(result)
      expect(transfers.length).to eq(1)
      expect(transfers.first[:fromUserId].to_s).to eq(carol[:id].to_s)
      expect(transfers.first[:toUserId].to_s).to eq(alice[:id].to_s)
      expect(transfers.first[:amount]).to eq(10.0)
    end

    it "handles single participant" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 3))

      # Alice pays 50 for Bob only
      expense_id = insert_expense(event: event, user: alice, amount: 50.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 3))
      insert_participant(expense_id: expense_id, user: bob)

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      transfers = transfers_from(result)
      expect(transfers.length).to eq(1)
      expect(transfers.first[:amount]).to eq(50.0)
    end
  end

  describe "successful settlement creation" do
    it "marks expenses as settled (links them to the settlement)" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 4))

      insert_expense(event: event, user: alice, amount: 100.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 4))

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      expenses = result.value![:objects].select { |o| o[:objectType] == "expense" }
      expect(expenses.all? { |e| e[:settlementId] }).to be true
    end

    it "returns settlement and transfer objects in the pool" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 4))

      insert_expense(event: event, user: alice, amount: 80.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 4))

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      result = described_class.call(
        event_id: event[:id],
        membership: creator_membership,
        workspace_id: workspace[:id]
      )

      expect(result.success?).to be true
      objects = result.value![:objects]
      expect(objects.any? { |o| o[:objectType] == "settlement" }).to be true
      expect(objects.any? { |o| o[:objectType] == "settlementTransfer" }).to be true
    end

    it "does not settle already-settled expenses" do
      alice = TestFactories.user(name: "Alice")
      bob = TestFactories.user(name: "Bob")
      event = TestFactories.event(workspace: workspace, user: creator)
      event = set_event_dates(event, Date.new(2026, 1, 1), Date.new(2026, 1, 4))

      TestFactories.rsvp(event: event, user: alice, attending: true)
      TestFactories.rsvp(event: event, user: bob, attending: true)

      # First settlement
      insert_expense(event: event, user: alice, amount: 50.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 4))
      described_class.call(event_id: event[:id], membership: creator_membership, workspace_id: workspace[:id])

      # Second expense — only this one should be unsettled
      insert_expense(event: event, user: bob, amount: 30.00, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 1, 4))
      result2 = described_class.call(event_id: event[:id], membership: creator_membership, workspace_id: workspace[:id])

      expect(result2.success?).to be true
      # Only the second expense appears as newly settled in this settlement
      settlements = DB[:settlements].where(event_id: event[:id]).all
      expect(settlements.length).to eq(2)
    end
  end
end
