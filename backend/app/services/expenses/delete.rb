# frozen_string_literal: true

module Expenses
  # Service to delete an expense. Creator-only.
  module Delete
    class << self
      include Dry::Monads[:result]

      def call(expense_id:, membership:, workspace_id:)
        # Mutated inside the chain once the expense is loaded so the audit
        # row carries who the action was about, not just who did it.
        audit_context = {}

        Auditable.around(
          service: "Expenses::Delete",
          actor: membership,
          subject_type: "expense",
          subject_id: expense_id,
          workspace_id: workspace_id,
          context: audit_context
        ) do
          Success()
            .bind { Expense.find_result(expense_id) }
            .bind { |expense| record_subject(audit_context, expense) }
            .bind { |expense| ExpensePolicy.enforce(:delete, expense, membership: membership) }
            .bind { |expense| delete_expense(expense, workspace_id) }
        end
      end

      private

      def record_subject(audit_context, expense)
        audit_context[:subject_user_id] = expense.user_id&.to_s
        Success(expense)
      end

      def delete_expense(expense, workspace_id)
        expense_id = expense.id

        DB.transaction do
          # Track participant deletions before CASCADE removes them. Broadcast
          # each so live clients on permission paths that don't cascade still
          # see the participants disappear.
          ExpenseParticipant.for_expense(expense_id).each do |p|
            DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "expense_participant", object_id: p.id)
            Broadcaster.object_deleted("expense_participant", p.id, workspace_id: workspace_id)
          end

          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "expense", object_id: expense_id)
          DB[:expenses].where(id: expense_id).delete
          Broadcaster.object_deleted("expense", expense_id, workspace_id: workspace_id)
        end

        Success({ deleted: [{ objectType: "expense", id: expense_id.to_s }] })
      end
    end
  end
end
