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
               .bind { |expense| check_not_settled(expense) }
               .bind { |expense| check_owner(expense, current_user_id) }
               .bind { |expense| delete_expense(expense, workspace_id) }
      end

      private

      sig { params(expense: Expense).returns(Result[Expense, ServiceError]) }
      def check_not_settled(expense)
        if expense.settlement_id
          T.cast(
            Failure(ServiceError.validation("Expense is part of a settlement. Delete the settlement first to edit.")),
            Result[Expense, ServiceError]
          )
        else
          T.cast(Success(expense), Result[Expense, ServiceError])
        end
      end

      sig do
        params(expense: Expense, current_user_id: T.any(String, UUID))
          .returns(Result[Expense, ServiceError])
      end
      def check_owner(expense, current_user_id)
        if expense.user_id&.to_s == current_user_id.to_s
          T.cast(Success(expense), Result[Expense, ServiceError])
        else
          T.cast(Failure(ServiceError.forbidden("Not authorized to delete this expense")), Result[Expense, ServiceError])
        end
      end

      sig do
        params(expense: Expense, workspace_id: T.any(String, UUID))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def delete_expense(expense, workspace_id)
        expense_id = expense.id

        DB.transaction do
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
