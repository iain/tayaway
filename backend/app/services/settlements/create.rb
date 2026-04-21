# frozen_string_literal: true

module Settlements
  # Service to create a settlement for an event. Computes balances from expenses
  # and attending RSVPs, then minimizes transfers using a greedy algorithm.
  #
  # Settlements form an immutable chain. When a prior settlement exists for the
  # event, a new call becomes a "top-up" that links to the prior tip via
  # previous_settlement_id and only captures the delta since then: the share
  # change for already-settled expenses (because RSVPs moved) plus the full
  # balance for any new unsettled expenses. Each settlement snapshots the
  # attending RSVPs that its math assumed, so a later top-up can diff against
  # the prior assumption rather than recomputing history.
  module Create
    class << self
      include Dry::Monads[:result]

      def call(event_id:, membership:, workspace_id:)
        Event.find_result(event_id)
             .bind { |event| EventPolicy.enforce(:create_settlement, event, membership: membership) }
             .bind { |event| check_event_dates(event) }
             .bind { |event| settle(event, membership, workspace_id) }
      end

      private

      def check_event_dates(event)
        if event.start_date && event.end_date
          Success(event)
        else
          Failure(ServiceError.validation("Event must have dates set before settling expenses"))
        end
      end

      # Run the entire settlement inside a single transaction with row-level locking.
      # This prevents concurrent mutations from causing stale-data settlements and
      # prevents two clients from both chaining a top-up onto the same tip.
      def settle(event, membership, workspace_id)
        settlement_id = SecureRandom.uuid
        now = Time.now

        DB.transaction do
          tip = Settlement.tip_for_event(event.id)
          if tip
            DB[:settlements].where(id: tip.id).for_update.first
            if Settlement.successor?(tip.id)
              return Failure(ServiceError.validation("These expenses were just settled by another member"))
            end
          end

          unsettled = DB[:expenses]
                      .where(event_id: event.id, settlement_id: nil)
                      .for_update
                      .order(:created_at)
                      .all
          settled = DB[:expenses]
                    .where(event_id: event.id)
                    .exclude(settlement_id: nil)
                    .order(:created_at)
                    .all

          if unsettled.empty? && settled.empty?
            error_message = concurrent_settlement_exists?(event.id) ?
              "These expenses were just settled by another member" :
              "No unsettled expenses to settle"
            return Failure(ServiceError.validation(error_message))
          end

          current_rsvps = Rsvp.for_event(event.id).select(&:attending)
          if current_rsvps.empty? && tip.nil?
            return Failure(ServiceError.validation("No attending RSVPs found for this event"))
          end

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

          if unsettled.empty? && transfers.empty?
            error_message = concurrent_settlement_exists?(event.id) ?
              "These expenses were just settled by another member" :
              "Nothing to settle — the split is already up to date"
            return Failure(ServiceError.validation(error_message))
          end

          DB[:settlements].insert(
            id: settlement_id,
            event_id: event.id,
            user_id: membership.user_id,
            previous_settlement_id: tip&.id,
            rsvp_snapshot: Sequel.pg_jsonb({ "rsvps" => current_snapshot }),
            created_at: now,
            updated_at: now
          )

          transfers.each do |transfer|
            transfer_id = SecureRandom.uuid
            DB[:settlement_transfers].insert(
              id: transfer_id,
              settlement_id: settlement_id,
              from_user_id: transfer[:from_user_id],
              to_user_id: transfer[:to_user_id],
              amount: transfer[:amount],
              created_at: now,
              updated_at: now
            )
            Broadcaster.object_changed("settlement_transfer", transfer_id, workspace_id: workspace_id)
          end

          unless unsettled.empty?
            DB[:expenses]
              .where(event_id: event.id, settlement_id: nil)
              .update(settlement_id: settlement_id, updated_at: now)
          end

          Broadcaster.object_changed("settlement", settlement_id, workspace_id: workspace_id)
        end

        all_expenses = Expense.for_event(event.id)
        all_expenses.select { |e| e.settlement_id&.to_s == settlement_id }.each do |expense|
          Broadcaster.object_changed("expense", expense.id, workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(membership: membership)
        settlement = Settlement.find(settlement_id)
        pool.add(:settlement, [settlement])
        pool.add(:settlement_transfer, SettlementTransfer.for_settlement(settlement_id))
        pool.add(:expense, all_expenses)

        Success({ objects: pool.to_a })
      end

      # Returns true if a settlement for this event was created within the last 5 seconds,
      # indicating a concurrent settlement request just completed ahead of this one.
      def concurrent_settlement_exists?(event_id)
        DB[:settlements]
          .where(event_id: event_id)
          .where(Sequel.expr(:created_at) >= Time.now - 5)
          .any?
      end
    end
  end
end
