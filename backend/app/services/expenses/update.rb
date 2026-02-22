# typed: true
# frozen_string_literal: true

module Expenses
  # Service to update an expense (description and/or amount). Creator-only.
  module Update
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          expense_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID),
          description: T.nilable(String),
          amount: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(expense_id:, current_user_id:, workspace_id:, description:, amount:)
        Expense.find_result(expense_id)
               .bind { |expense| check_owner(expense, current_user_id) }
               .bind { |expense| validate_update(expense, description, amount) }
               .bind { |expense| update_expense(expense, workspace_id, description, amount) }
      end

      private

      sig do
        params(expense: Expense, current_user_id: T.any(String, UUID))
          .returns(Result[Expense, ServiceError])
      end
      def check_owner(expense, current_user_id)
        if expense.user_id&.to_s == current_user_id.to_s
          T.cast(Success(expense), Result[Expense, ServiceError])
        else
          T.cast(Failure(ServiceError.forbidden("Not authorized to update this expense")), Result[Expense, ServiceError])
        end
      end

      sig do
        params(expense: Expense, description: T.nilable(String), amount: T.nilable(Float))
          .returns(Result[Expense, ServiceError])
      end
      def validate_update(expense, description, amount)
        has_description = description && !description.empty?
        has_amount = !amount.nil?

        if !has_description && !has_amount
          return T.cast(
            Failure(ServiceError.validation("Description or amount is required")),
            Result[Expense, ServiceError]
          )
        end

        if has_amount && T.must(amount) <= 0
          return T.cast(
            Failure(ServiceError.validation("Amount must be greater than zero")),
            Result[Expense, ServiceError]
          )
        end

        T.cast(Success(expense), Result[Expense, ServiceError])
      end

      sig do
        params(
          expense: Expense,
          workspace_id: T.any(String, UUID),
          description: T.nilable(String),
          amount: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_expense(expense, workspace_id, description, amount)
        DB.transaction do
          updates = { updated_at: Time.now }
          updates[:description] = description if description && !description.empty?
          updates[:amount] = amount unless amount.nil?
          DB[:expenses].where(id: expense.id).update(updates)
          Broadcaster.object_changed("expense", expense.id, workspace_id: workspace_id)
        end

        updated = T.must(Expense.find(expense.id))
        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_expense(updated)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
