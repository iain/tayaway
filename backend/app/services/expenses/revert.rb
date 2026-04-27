# frozen_string_literal: true

module Expenses
  # Create a mirror-image expense that offsets an existing one. The reverted
  # expense remains in the ledger; the revert is a new unsettled row that
  # flows into the next settlement.
  module Revert
    class << self
      include Dry::Monads[:result]

      def call(expense_id:, membership:, workspace_id:)
        # Mutated inside the chain once the expense is loaded so the audit
        # row carries who the action was about, not just who did it.
        audit_context = {}

        Auditable.around(
          service: "Expenses::Revert",
          actor: membership,
          subject_type: "expense",
          subject_id: expense_id,
          workspace_id: workspace_id,
          context: audit_context
        ) do
          Success()
            .bind { Expense.find_result(expense_id) }
            .bind { |expense| record_subject(audit_context, expense) }
            .bind { |expense| load_event(expense) }
            .bind { |expense, event| ExpensePolicy.enforce(:revert, expense, membership: membership, event: event).fmap { [expense, event] } }
            .bind { |expense, event| check_event_ready(expense, event) }
            .bind { |expense| insert_revert(expense, membership, workspace_id) }
        end
      end

      private

      def record_subject(audit_context, expense)
        audit_context[:subject_user_id] = expense.user_id&.to_s
        Success(expense)
      end

      def load_event(expense)
        event = Event.find(expense.event_id)
        if event
          Success([expense, event])
        else
          Failure(ServiceError.not_found("Event not found"))
        end
      end

      # The revert copies the original's dates verbatim. If the event has
      # since lost its date range the downstream math becomes unsafe.
      def check_event_ready(expense, event)
        if event.start_date.nil? || event.end_date.nil?
          Failure(ServiceError.validation("Event is missing dates — cannot revert"))
        else
          Success(expense)
        end
      end

      def insert_revert(original, membership, workspace_id)
        revert_id = SecureRandom.uuid
        now = Time.now

        inserted = nil
        DB.transaction do
          # ON CONFLICT on the partial unique index means concurrent revert
          # attempts serialize at the DB; the loser gets back nil and we bail.
          inserted = DB[:expenses]
                     .returning(:id)
                     .insert_conflict(
                       target: :reverts_expense_id,
                       conflict_where: Sequel.lit("reverts_expense_id IS NOT NULL")
                     )
                     .insert(
                       id: revert_id,
                       event_id: original.event_id,
                       user_id: original.user_id,
                       created_by_user_id: membership.user_id,
                       reverts_expense_id: original.id,
                       amount: -original.amount,
                       description: "Reverts: #{original.description}",
                       start_date: original.start_date,
                       end_date: original.end_date,
                       created_at: now,
                       updated_at: now
                     )
                     .first

          next unless inserted

          ExpenseParticipant.for_expense(original.id).each do |participant|
            participant_id = SecureRandom.uuid
            DB[:expense_participants].insert(
              id: participant_id,
              expense_id: revert_id,
              user_id: participant.user_id,
              factor: participant.factor,
              created_at: now,
              updated_at: now
            )
            Broadcaster.object_changed("expense_participant", participant_id, workspace_id: workspace_id)
          end

          Broadcaster.object_changed("expense", revert_id, workspace_id: workspace_id)
          # The original's permissions change (revert becomes disallowed) so
          # clients need to refresh it too.
          Broadcaster.object_changed("expense", original.id, workspace_id: workspace_id)
        end

        return Failure(ServiceError.validation("This expense has already been reverted")) unless inserted

        pool = PoolSerializer.new(membership: membership)
        revert = Expense.find(revert_id)
        return Failure(ServiceError.conflict("Revert was not persisted; retry")) if revert.nil?

        refreshed_original = Expense.find(original.id)
        pool.add(:expense, [revert, refreshed_original].compact)
        Success({ objects: pool.to_a })
      rescue Sequel::ForeignKeyConstraintViolation
        Failure(ServiceError.validation("This expense was just deleted"))
      end
    end
  end
end
