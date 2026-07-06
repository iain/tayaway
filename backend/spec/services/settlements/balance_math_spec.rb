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
end
