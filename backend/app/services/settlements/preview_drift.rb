# frozen_string_literal: true

module Settlements
  # Read-only preview of the next top-up. Callers must authorize workspace
  # access; this service does not.
  module PreviewDrift
    class << self
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

        current_attendances = Attendance.for_event(event.id).select(&:going?)
        if current_attendances.empty?
          return Success(empty_preview(tip))
        end

        current_snapshot = BalanceMath.snapshot_attendances(current_attendances, event)

        all_expenses = unsettled + settled
        expense_ids = all_expenses.map { |e| e[:id].to_s }
        participants_by_expense = ExpenseParticipant.for_expenses(expense_ids)

        active_transfers = DB[:settlement_transfers]
                           .join(:settlements, id: :settlement_id)
                           .where(Sequel[:settlements][:event_id] => event.id)
                           .where(Sequel[:settlement_transfers][:superseded_at] => nil)
                           .select_all(:settlement_transfers)
                           .all
        paid_transfers = active_transfers.reject { |t| t[:paid_at].nil? }

        residual = BalanceMath.compute_balances(
          expenses: all_expenses,
          current_snapshot: current_snapshot,
          participants_by_expense: participants_by_expense,
          credited_transfers: active_transfers
        )
        # Sub-half-cent residuals can survive rounding without being able to
        # fund any transfer. Match Create's gate so we don't tell the user
        # there's drift when the books are already up to date.
        if unsettled.empty? && BalanceMath.minimize_transfers(residual).empty?
          return Success(empty_preview(tip))
        end

        balances = BalanceMath.compute_balances(
          expenses: all_expenses,
          current_snapshot: current_snapshot,
          participants_by_expense: participants_by_expense,
          credited_transfers: paid_transfers
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
      rescue BalanceMath::InputError => e
        Failure(ServiceError.conflict(e.message))
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
