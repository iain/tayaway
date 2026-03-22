# typed: true
# frozen_string_literal: true

module Settlements
  # Service to create a settlement for an event. Computes balances from expenses
  # and attending RSVPs, then minimizes transfers using a greedy algorithm.
  module Create
    # Minimum absolute balance (in euros) treated as zero. Balances and transfer
    # amounts below this threshold are ignored to avoid spurious micro-transfers
    # from floating-point rounding after two decimal places of precision.
    BALANCE_EPSILON = 0.005

    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, user_id:, workspace_id:)
        find_event(event_id)
          .bind { |event| check_event_dates(event) }
          .bind { |event| settle(event, user_id, workspace_id) }
      end

      private

      sig { params(event_id: T.any(String, UUID)).returns(Result[Event, ServiceError]) }
      def find_event(event_id)
        Event.find_result(event_id)
      end

      sig { params(event: Event).returns(Result[Event, ServiceError]) }
      def check_event_dates(event)
        if event.start_date && event.end_date
          T.cast(Success(event), Result[Event, ServiceError])
        else
          T.cast(
            Failure(ServiceError.validation("Event must have dates set before settling expenses")),
            Result[Event, ServiceError]
          )
        end
      end

      # Run the entire settlement inside a single transaction with row-level locking.
      # This prevents concurrent expense mutations from causing stale-data settlements.
      sig do
        params(
          event: Event,
          user_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def settle(event, user_id, workspace_id)
        settlement_id = SecureRandom.uuid
        now = Time.now

        DB.transaction do
          # Lock unsettled expenses for this event — prevents concurrent create/update/delete
          # from changing them while we compute balances.
          expenses = DB[:expenses]
                     .where(event_id: event.id, settlement_id: nil)
                     .for_update
                     .order(:created_at)
                     .all

          if expenses.empty?
            error_message = concurrent_settlement_exists?(event.id) ?
              "These expenses were just settled by another member" :
              "No unsettled expenses to settle"
            return T.cast(
              Failure(ServiceError.validation(error_message)),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
          end

          rsvps = Rsvp.for_event(event.id).select(&:attending)

          if rsvps.empty?
            return T.cast(
              Failure(ServiceError.validation("No attending RSVPs found for this event")),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
          end

          balances = compute_balances(event, expenses, rsvps)
          transfers = minimize_transfers(balances)

          DB[:settlements].insert(
            id: settlement_id,
            event_id: event.id,
            user_id: user_id,
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

          DB[:expenses]
            .where(event_id: event.id, settlement_id: nil)
            .update(settlement_id: settlement_id, updated_at: now)

          Broadcaster.object_changed("settlement", settlement_id, workspace_id: workspace_id)
        end

        # Load expenses once after the transaction for both broadcasting and serialization
        all_expenses = Expense.for_event(event.id)
        all_expenses.select { |e| e.settlement_id&.to_s == settlement_id }.each do |expense|
          Broadcaster.object_changed("expense", expense.id, workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)
        settlement = T.must(Settlement.find(settlement_id))
        pool.add_settlement(settlement)
        SettlementTransfer.for_settlement(settlement_id).each { |t| pool.add_settlement_transfer(t) }
        all_expenses.each { |e| pool.add_expense(e) }

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end

      # Returns true if a settlement for this event was created within the last 5 seconds,
      # indicating a concurrent settlement request just completed ahead of this one.
      sig { params(event_id: T.any(String, UUID)).returns(T::Boolean) }
      def concurrent_settlement_exists?(event_id)
        DB[:settlements]
          .where(event_id: event_id)
          .where(Sequel.expr(:created_at) >= Time.now - 5)
          .any?
      end

      # Compute net balance for each user: share - paid
      # Positive balance means user owes money; negative means user is owed money
      sig do
        params(
          event: Event,
          expenses: T::Array[T.untyped],
          rsvps: T::Array[Rsvp]
        ).returns(T::Hash[String, Float])
      end
      def compute_balances(event, expenses, rsvps)
        share_by_user = Hash.new(0.0)
        paid_by_user = Hash.new(0.0)

        event_start = T.must(event.start_date)
        event_end = T.must(event.end_date)

        # Pre-compute RSVP effective dates
        rsvp_dates = rsvps.map do |rsvp|
          {
            user_id: rsvp.user_id.to_s,
            start_date: rsvp.start_date || event_start,
            end_date: rsvp.end_date || event_end
          }
        end

        # Batch-load participants for all expenses
        expense_ids = expenses.map { |e| e[:id].to_s }
        participants_by_expense = ExpenseParticipant.for_expenses(expense_ids)

        expenses.each do |expense|
          expense_id = expense[:id].to_s
          expense_amount = expense[:amount].to_f

          # Track who paid
          if expense[:user_id]
            paid_by_user[expense[:user_id].to_s] += expense_amount
          end

          participants = participants_by_expense[expense_id] || []

          if participants.any?
            # Equal split among explicit participants
            share = expense_amount / participants.length
            participants.each do |p|
              share_by_user[p.user_id.to_s] += share
            end
          else
            # RSVP overlap logic (unchanged)
            expense_start = expense[:start_date]
            expense_end = expense[:end_date]

            overlaps = []
            rsvp_dates.each do |rd|
              overlap_start = [expense_start, rd[:start_date]].max
              overlap_end = [expense_end, rd[:end_date]].min

              next if overlap_start > overlap_end

              overlap_days = (overlap_end - overlap_start).to_i + 1
              next if overlap_days <= 0

              overlaps << { user_id: rd[:user_id], days: overlap_days }
            end

            total_overlap_days = overlaps.sum { |o| o[:days] }
            next if total_overlap_days == 0

            overlaps.each do |o|
              overlap_share = (o[:days].to_f / total_overlap_days) * expense_amount
              share_by_user[o[:user_id]] += overlap_share
            end
          end
        end

        # Net balance: positive = owes money, negative = owed money
        all_user_ids = (share_by_user.keys + paid_by_user.keys).uniq
        balances = {}
        all_user_ids.each do |uid|
          balance = (share_by_user[uid] - paid_by_user[uid]).round(2).to_f
          balances[uid] = balance unless balance.abs < BALANCE_EPSILON
        end

        balances
      end

      # Greedy algorithm to minimize transfers
      sig { params(balances: T::Hash[String, Float]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def minimize_transfers(balances)
        debtors = balances.select { |_, v| v > 0 }.sort_by { |_, v| -v }.map { |k, v| [k, v] }
        creditors = balances.select { |_, v| v < 0 }.sort_by { |_, v| v }.map { |k, v| [k, -v] }

        transfers = []
        d_idx = 0
        c_idx = 0

        while d_idx < debtors.length && c_idx < creditors.length
          debtor_id, debt = T.must(debtors[d_idx])
          creditor_id, credit = T.must(creditors[c_idx])

          amount = [debt, credit].min.round(2).to_f

          if amount > BALANCE_EPSILON
            transfers << {
              from_user_id: debtor_id,
              to_user_id: creditor_id,
              amount: amount
            }
          end

          remaining_debt = (debt - amount).round(2).to_f
          remaining_credit = (credit - amount).round(2).to_f
          debtors[d_idx] = [debtor_id, remaining_debt]
          creditors[c_idx] = [creditor_id, remaining_credit]

          d_idx += 1 if remaining_debt < BALANCE_EPSILON
          c_idx += 1 if remaining_credit < BALANCE_EPSILON
        end

        transfers
      end
    end
  end
end
