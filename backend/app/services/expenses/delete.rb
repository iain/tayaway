# frozen_string_literal: true

module Expenses
  # Service to delete an expense. Creator-only.
  module Delete
    class << self
      include Dry::Monads[:result]

      def call(expense_id:, membership:, workspace_id:)
        Expense.find_result(expense_id)
               .bind { |expense| authorize(expense, membership) }
               .bind { |expense| delete_expense(expense, workspace_id) }
      end

      private

      def authorize(expense, membership)
        ExpensePolicy.new(expense, membership: membership)
                     .delete
                     .bind { Success(expense) }
                     .or { |reason| Failure(ServiceError.forbidden(reason.to_s)) }
      end

      def delete_expense(expense, workspace_id)
        expense_id = expense.id

        DB.transaction do
          # Track participant deletions before CASCADE removes them
          ExpenseParticipant.for_expense(expense_id).each do |p|
            DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "expense_participant", object_id: p.id)
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
