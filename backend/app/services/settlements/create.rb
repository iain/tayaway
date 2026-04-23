# frozen_string_literal: true

module Settlements
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

      def settle(event, membership, workspace_id)
        settlement_id = SecureRandom.uuid
        now = Time.now
        failure = nil

        DB.transaction do
          # Event-level lock serializes concurrent settlement attempts for the
          # same event. Without it, two callers who both observe an empty chain
          # could each insert a root settlement and fork the chain.
          DB[:events].where(id: event.id).for_update.first

          tip = Settlement.tip_for_event(event.id)
          if tip
            if Settlement.successor?(tip.id)
              failure = Failure(ServiceError.validation("These expenses were just settled by another member"))
              raise Sequel::Rollback
            end
            if tip.rsvp_snapshot.nil?
              failure = Failure(ServiceError.validation(
                                  "This event's prior settlement is missing its RSVP snapshot — run the backfill before settling again"
                                )
                               )
              raise Sequel::Rollback
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
            failure = Failure(ServiceError.validation(
                                concurrent_settlement_exists?(event.id) ?
                                  "These expenses were just settled by another member" :
                                  "No unsettled expenses to settle"
                              )
                             )
            raise Sequel::Rollback
          end

          current_rsvps = Rsvp.for_event(event.id).select(&:attending)
          if current_rsvps.empty?
            if tip.nil?
              failure = Failure(ServiceError.validation("No attending RSVPs found for this event"))
              raise Sequel::Rollback
            elsif !unsettled.empty?
              failure = Failure(ServiceError.validation("No one is currently attending — can't split the new expenses"))
              raise Sequel::Rollback
            end
          end

          current_snapshot = BalanceMath.snapshot_rsvps(current_rsvps, event)
          prior_snapshot = tip&.rsvp_snapshot&.dig("rsvps")

          expense_ids = (unsettled + settled).map { |e| e[:id].to_s }
          participants_by_expense = ExpenseParticipant.for_expenses(expense_ids)

          begin
            balances = BalanceMath.compute_balances(
              unsettled_expenses: unsettled,
              settled_expenses: settled,
              current_snapshot: current_snapshot,
              prior_snapshot: prior_snapshot,
              participants_by_expense: participants_by_expense
            )
          rescue BalanceMath::InputError => e
            failure = Failure(ServiceError.conflict(e.message))
            raise Sequel::Rollback
          end
          transfers = BalanceMath.minimize_transfers(balances)

          if unsettled.empty? && transfers.empty?
            failure = Failure(ServiceError.validation(
                                concurrent_settlement_exists?(event.id) ?
                                  "These expenses were just settled by another member" :
                                  "Nothing to settle — the split is already up to date"
                              )
                             )
            raise Sequel::Rollback
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

          if unsettled.any?
            DB[:expenses]
              .where(event_id: event.id, settlement_id: nil)
              .update(settlement_id: settlement_id, updated_at: now)
          end

          Broadcaster.object_changed("settlement", settlement_id, workspace_id: workspace_id)
          # Re-broadcast the prior tip so clients recompute "can delete" — it
          # flips once a successor exists.
          Broadcaster.object_changed("settlement", tip.id, workspace_id: workspace_id) if tip
        end

        return failure if failure

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

      def concurrent_settlement_exists?(event_id)
        DB[:settlements]
          .where(event_id: event_id)
          .where(Sequel.expr(:created_at) >= Time.now - 5)
          .any?
      end
    end
  end
end
