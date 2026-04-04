# typed: true
# frozen_string_literal: true

module Expenses
  # Service to delete an expense. Creator-only.
  module Delete
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          expense_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(expense_id:, current_user_id:, workspace_id:)
        Expense.find_result(expense_id)
               .bind { |expense| ExpensePolicy.new(expense: expense, user_id: current_user_id.to_s).authorize!(:delete, value: expense) }
               .bind { |expense| delete_expense(expense, workspace_id) }
      end

      private

      sig do
        params(expense: Expense, workspace_id: T.any(String, UUID))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
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

        T.cast(
          Success({ deleted: [{ objectType: "expense", id: expense_id.to_s }] }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end
    end
  end
end
