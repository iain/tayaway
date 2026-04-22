# frozen_string_literal: true

module Settlements
  # Read-only: computes what a top-up settlement *would* produce right now for
  # the tip of an event's settlement chain, without persisting anything.
  # Provides a server-authoritative parity check; the UI currently derives an
  # equivalent preview client-side. Callers must authorize workspace access
  # before invoking — the service itself does not.
  module PreviewDrift
    class << self
      include Dry::Monads[:result]

      def call(event_id:)
        Event.find_result(event_id)
             .bind { |event| preview(event) }
      end

      private

      def preview(event)
        tip = Settlement.tip_for_event(event.id)
        unsettled = DB[:expenses].where(event_id: event.id, settlement_id: nil).order(:created_at).all
        settled = DB[:expenses].where(event_id: event.id).exclude(settlement_id: nil).order(:created_at).all

        if unsettled.empty? && settled.empty?
          return Success(empty_preview(tip))
        end

        current_rsvps = Rsvp.for_event(event.id).select(&:attending)
        current_snapshot = BalanceMath.snapshot_rsvps(current_rsvps, event)
        prior_snapshot = tip&.rsvp_snapshot&.dig("rsvps")

        expense_ids = (unsettled + settled).map { |e| e[:id].to_s }
        participants_by_expense = ExpenseParticipant.for_expenses(expense_ids)

        balances = BalanceMath.compute_balances(
          unsettled_expenses: unsettled,
          settled_expenses: settled,
          current_snapshot: current_snapshot,
          prior_snapshot: prior_snapshot,
          participants_by_expense: participants_by_expense
        )
        transfers = BalanceMath.minimize_transfers(balances)

        Success(
          hasTip: !tip.nil?,
          settlementId: tip&.id&.to_s,
          hasUnsettledExpenses: !unsettled.empty?,
          balances: balances.map { |user_id, amount| { userId: user_id, amount: amount } },
          transfers: transfers.map { |t|
            { fromUserId: t[:from_user_id], toUserId: t[:to_user_id], amount: t[:amount] }
          }
        )
      end

      def empty_preview(tip)
        {
          hasTip: !tip.nil?,
          settlementId: tip&.id&.to_s,
          hasUnsettledExpenses: false,
          balances: [],
          transfers: []
        }
      end
    end
  end
end
