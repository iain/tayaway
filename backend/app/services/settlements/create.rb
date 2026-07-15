# frozen_string_literal: true

module Settlements
  module Create
    class << self
      def call(event_id:, membership:, workspace_id:)
        Auditable.around(
          service: "Settlements::Create",
          actor: membership,
          subject_type: "settlement",
          workspace_id: workspace_id
        ) do
          Success()
            .bind { Event.find_result(event_id) }
            .bind { |event| EventPolicy.enforce(:create_settlement, event, membership: membership) }
            .bind { |event| check_event_dates(event) }
            .bind { |event| settle(event, membership, workspace_id) }
        end
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
        superseded_ids = []
        committed_transfers = []

        DB.transaction do
          # Event-level lock serializes concurrent settlement attempts for the
          # same event. Without it, two callers who both observe an empty chain
          # could each insert a root settlement and fork the chain.
          DB[:events].where(id: event.id).for_update.first

          tip = Settlement.tip_for_event(event.id)
          if tip && Settlement.successor?(tip.id)
            failure = Failure(ServiceError.validation("These expenses were just settled by another member"))
            raise Sequel::Rollback
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

          current_attendances = Attendance.for_event(event.id).select(&:going?)
          if current_attendances.empty?
            message =
              if tip.nil?
                "No one is marked as going on this event"
              elsif !unsettled.empty?
                "No one is currently attending — can't split the new expenses"
              else
                "No one is currently attending — can't settle the drift"
              end
            failure = Failure(ServiceError.validation(message))
            raise Sequel::Rollback
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

          begin
            # Residual credits both paid and unpaid transfers: if minimizing
            # it produces no transfer AND no new expenses have been added,
            # the books already reflect the fair split. We check via
            # `minimize_transfers` rather than `residual.empty?` because
            # per-user residuals up to half a cent can survive as rounding
            # crumbs from the prior top-up — those can't fund any transfer
            # and shouldn't trigger a fresh issue.
            residual_balance = BalanceMath.compute_balances(
              expenses: all_expenses,
              current_snapshot: current_snapshot,
              participants_by_expense: participants_by_expense,
              credited_transfers: active_transfers
            )
          rescue BalanceMath::InputError => e
            failure = Failure(ServiceError.conflict(e.message))
            raise Sequel::Rollback
          end

          if unsettled.empty? && BalanceMath.minimize_transfers(residual_balance).empty?
            failure = Failure(ServiceError.validation(
                                concurrent_settlement_exists?(event.id) ?
                                  "These expenses were just settled by another member" :
                                  "Nothing to settle — the split is already up to date"
                              )
                             )
            raise Sequel::Rollback
          end

          # Fresh balance credits paid transfers only. Unpaid priors are
          # superseded below, so the new transfer set replaces them wholesale
          # instead of stacking counter-transfers on top.
          balances = BalanceMath.compute_balances(
            expenses: all_expenses,
            current_snapshot: current_snapshot,
            participants_by_expense: participants_by_expense,
            credited_transfers: paid_transfers
          )
          transfers = BalanceMath.minimize_transfers(balances)

          DB[:settlements].insert(
            id: settlement_id,
            event_id: event.id,
            user_id: membership.user_id,
            previous_settlement_id: tip&.id,
            rsvp_snapshot: Sequel.pg_jsonb({ "attendances" => current_snapshot }),
            created_at: now,
            updated_at: now
          )

          if tip
            superseded_ids = DB[:settlement_transfers]
                             .join(:settlements, id: :settlement_id)
                             .where(Sequel[:settlements][:event_id] => event.id)
                             .where(Sequel[:settlement_transfers][:paid_at] => nil)
                             .where(Sequel[:settlement_transfers][:superseded_at] => nil)
                             .select_map(Sequel[:settlement_transfers][:id])
            if superseded_ids.any?
              DB[:settlement_transfers]
                .where(id: superseded_ids)
                .update(superseded_at: now, updated_at: now)
            end
          end

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
            Broadcaster.object_changed("settlement_transfer", transfer_id)
          end
          committed_transfers = transfers

          if unsettled.any?
            # Target rows by the locked ids rather than re-evaluating
            # `settlement_id IS NULL` — a concurrent insert between the locked
            # SELECT above and this UPDATE would otherwise get swept in
            # without appearing in the balance math.
            unsettled_ids = unsettled.map { |e| e[:id] }
            DB[:expenses]
              .where(id: unsettled_ids)
              .update(settlement_id: settlement_id, updated_at: now)
          end

          superseded_ids.each do |tid|
            Broadcaster.object_changed("settlement_transfer", tid)
          end

          Broadcaster.object_changed("settlement", settlement_id)
          # Re-broadcast the prior tip so clients recompute "can delete" — it
          # flips once a successor exists.
          Broadcaster.object_changed("settlement", tip.id) if tip
        end

        return failure if failure

        all_expenses = Expense.for_event(event.id)
        all_expenses.select { |e| e.settlement_id&.to_s == settlement_id }.each do |expense|
          Broadcaster.object_changed("expense", expense.id)
        end

        Settlements::OnCreated.call(transfers: committed_transfers, event: event, workspace_id: workspace_id)

        pool = PoolSerializer.new(membership: membership)
        settlement = Settlement.find(settlement_id)
        pool.add(:settlement, [settlement])
        pool.add(:settlement_transfer, SettlementTransfer.for_settlement(settlement_id))
        if superseded_ids.any?
          pool.add(:settlement_transfer, superseded_ids.filter_map { |tid| SettlementTransfer.find(tid) })
        end
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
