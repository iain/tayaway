# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::BalanceMath do
  # Pure-function coverage for the Mode B (no explicit participants) day-set
  # split. Snapshots are hand-built in the shape snapshot_rsvps produces so the
  # math is exercised without touching the database.
  describe ".compute_balances (day-set overlap)" do
    let(:d) { Date.new(2026, 3, 1) }

    def snapshot(user_id, dates)
      { "user_id" => user_id, "dates" => dates.map(&:to_s) }
    end

    it "splits a whole-event expense equally among whole-event attendees" do
      expense = { id: "e1", user_id: "alice", amount: 90.0, start_date: d, end_date: d + 2 }
      snap = %w[alice bob carol].map { |u| snapshot(u, [d, d + 1, d + 2]) }

      balances = described_class.compute_balances(
        expenses: [expense], current_snapshot: snap, participants_by_expense: {}
      )

      # Fair share is 30 each; Alice paid 90.
      expect(balances["alice"]).to eq(-60.0)
      expect(balances["bob"]).to eq(30.0)
      expect(balances["carol"]).to eq(30.0)
    end

    it "splits proportionally to attended days within the expense window" do
      # 2-day, €100 expense. Alice present both days, Bob only day 1.
      expense = { id: "e1", user_id: "alice", amount: 100.0, start_date: d, end_date: d + 1 }
      snap = [snapshot("alice", [d, d + 1]), snapshot("bob", [d])]

      balances = described_class.compute_balances(
        expenses: [expense], current_snapshot: snap, participants_by_expense: {}
      )

      # Total overlap = 3 days; Bob 1/3·100 = 33.33 owed, Alice 2/3·100 − 100 paid.
      expect(balances["bob"]).to eq(33.33)
      expect(balances["alice"]).to eq(-33.33)
    end

    it "counts only the come-and-go days that fall inside the expense window" do
      # Expense covers only day 1. Bob comes and goes on days 2–3, not day 1.
      expense = { id: "e1", user_id: "alice", amount: 50.0, start_date: d, end_date: d }
      snap = [snapshot("alice", [d]), snapshot("bob", [d + 1, d + 2])]

      balances = described_class.compute_balances(
        expenses: [expense], current_snapshot: snap, participants_by_expense: {}
      )

      # Only Alice overlaps, she paid her own whole share → nobody owes anything.
      expect(balances).to eq({})
    end
  end

  describe ".compute_balances (per-day plus-ones)" do
    let(:d) { Date.new(2026, 3, 1) }

    # New snapshot shape: each day carries its own guest count. A guest is an
    # extra head on that day, absorbed by the host — guests hold no balance.
    def day(date, plus_ones = 0)
      { "date" => date.to_s, "plus_ones" => plus_ones }
    end

    def snapshot_days(user_id, days)
      { "user_id" => user_id, "days" => days }
    end

    def snapshot_dates(user_id, dates)
      { "user_id" => user_id, "dates" => dates.map(&:to_s) }
    end

    it "counts a guest as an extra head on the host's own share" do
      # €210 over 2 days. Alice present both days with a +1 each day; Bob present
      # both days alone. Head-days: Alice 4, Bob 2, total 6 → €35/head-day.
      expense = { id: "e1", user_id: "bob", amount: 210.0, start_date: d, end_date: d + 1 }
      snap = [
        snapshot_days("alice", [day(d, 1), day(d + 1, 1)]),
        snapshot_days("bob", [day(d), day(d + 1)])
      ]

      balances = described_class.compute_balances(
        expenses: [expense], current_snapshot: snap, participants_by_expense: {}
      )

      expect(balances["alice"]).to eq(140.0)
      expect(balances["bob"]).to eq(-140.0)
    end

    it "ignores guests on days outside the expense window" do
      # Expense covers day 1 only. Alice's +1 lands on day 2, so it adds no head
      # to the split — day 1 is an even 1-for-1 between Alice and Bob.
      expense = { id: "e1", user_id: "bob", amount: 100.0, start_date: d, end_date: d }
      snap = [
        snapshot_days("alice", [day(d, 0), day(d + 1, 5)]),
        snapshot_days("bob", [day(d)])
      ]

      balances = described_class.compute_balances(
        expenses: [expense], current_snapshot: snap, participants_by_expense: {}
      )

      # 2 heads on day 1 → €50 each; Bob paid 100 → −50, Alice owes 50.
      expect(balances["alice"]).to eq(50.0)
      expect(balances["bob"]).to eq(-50.0)
    end

    it "still reads the legacy flat `dates` snapshot as one head per day" do
      expense = { id: "e1", user_id: "alice", amount: 100.0, start_date: d, end_date: d + 1 }
      snap = [snapshot_dates("alice", [d, d + 1]), snapshot_dates("bob", [d])]

      balances = described_class.compute_balances(
        expenses: [expense], current_snapshot: snap, participants_by_expense: {}
      )

      # Same as the historical proportional-days split: total 3 head-days.
      expect(balances["bob"]).to eq(33.33)
      expect(balances["alice"]).to eq(-33.33)
    end

    it "bills a guest attendance's days to its billing user (the host)" do
      def attendance_entry(billing_user_id, dates, guest_id: nil)
        {
          "billing_user_id" => billing_user_id,
          "guest_id" => guest_id,
          "days" => dates.map(&:to_s)
        }
      end

      # Alice brings Emma for all three days; Bob pays €90 for the event.
      # Head-days: Alice 3 + Emma 3 (billed to Alice) = 6, Bob 3, total 9.
      expense = { id: "e1", user_id: "bob", amount: 90.0, start_date: d, end_date: d + 2 }
      snap = [
        attendance_entry("alice", [d, d + 1, d + 2]),
        attendance_entry("alice", [d, d + 1, d + 2], guest_id: "guest-emma"),
        attendance_entry("bob", [d, d + 1, d + 2])
      ]

      balances = described_class.compute_balances(
        expenses: [expense], current_snapshot: snap, participants_by_expense: {}
      )

      expect(balances["alice"]).to eq(60.0)
      expect(balances["bob"]).to eq(-60.0)
    end
  end

  describe ".minimize_transfers" do
    it "breaks balance ties by user id so output is independent of hash order" do
      entries = { "bob" => 50.0, "alice" => 50.0, "dave" => -50.0, "carol" => -50.0 }

      forward = described_class.minimize_transfers(entries)
      reversed = described_class.minimize_transfers(entries.to_a.reverse.to_h)

      expect(forward).to eq(reversed)
      expect(forward).to eq(
        [
          { from_user_id: "alice", to_user_id: "carol", amount: 50.0 },
          { from_user_id: "bob", to_user_id: "dave", amount: 50.0 }
        ]
      )
    end
  end

  describe ".snapshot_attendances" do
    it "resolves member and guest rows to effective days and billing users" do
      workspace = TestFactories.workspace
      alice = TestFactories.user(name: "Alice")
      event_row = TestFactories.event(workspace: workspace, user: alice)
      DB[:events].where(id: event_row[:id]).update(start_date: Date.new(2026, 3, 1), end_date: Date.new(2026, 3, 3))
      event = Event.find(event_row[:id])
      member_row = TestFactories.attendance(event: event_row, user: alice)
      guest = TestFactories.guest(workspace: workspace, name: "Emma")
      guest_row = TestFactories.attendance(
        event: event_row, guest: guest, host: alice, days: [Date.new(2026, 3, 2)]
      )

      snapshot = described_class.snapshot_attendances(
        [Attendance.find(member_row[:id]), Attendance.find(guest_row[:id])], event
      )

      member_entry, guest_entry = snapshot
      expect(member_entry["billing_user_id"]).to eq(alice[:id])
      expect(member_entry["guest_id"]).to be_nil
      expect(member_entry["days"]).to eq(%w[2026-03-01 2026-03-02 2026-03-03])
      expect(guest_entry["billing_user_id"]).to eq(alice[:id])
      expect(guest_entry["guest_id"]).to eq(guest[:id])
      expect(guest_entry["display_name"]).to eq("Emma")
      expect(guest_entry["days"]).to eq(%w[2026-03-02])
    end
  end
end
