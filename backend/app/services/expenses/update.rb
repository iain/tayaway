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
          amount: T.nilable(Float),
          start_date: T.nilable(String),
          end_date: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(expense_id:, current_user_id:, workspace_id:, description:, amount:, start_date: nil, end_date: nil)
        Expense.find_result(expense_id)
               .bind { |expense| check_not_settled(expense) }
               .bind { |expense| check_owner(expense, current_user_id) }
               .bind { |expense| validate_update(expense, description, amount, start_date, end_date) }
               .bind { |expense| update_expense(expense, workspace_id, description, amount, start_date, end_date) }
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
          T.cast(Failure(ServiceError.forbidden("Not authorized to update this expense")), Result[Expense, ServiceError])
        end
      end

      sig do
        params(
          expense: Expense,
          description: T.nilable(String),
          amount: T.nilable(Float),
          start_date: T.nilable(String),
          end_date: T.nilable(String)
        ).returns(Result[Expense, ServiceError])
      end
      def validate_update(expense, description, amount, start_date, end_date)
        has_description = description && !description.empty?
        has_amount = !amount.nil?
        has_dates = (start_date && !start_date.empty?) || (end_date && !end_date.empty?)

        if !has_description && !has_amount && !has_dates
          return T.cast(
            Failure(ServiceError.validation("Description, amount, or dates are required")),
            Result[Expense, ServiceError]
          )
        end

        if has_amount && T.must(amount) <= 0
          return T.cast(
            Failure(ServiceError.validation("Amount must be greater than zero")),
            Result[Expense, ServiceError]
          )
        end

        if has_dates
          sd = start_date && !start_date.empty? ? start_date : nil
          ed = end_date && !end_date.empty? ? end_date : nil
          unless sd && ed
            return T.cast(
              Failure(ServiceError.validation("Both start date and end date are required")),
              Result[Expense, ServiceError]
            )
          end
          if sd > ed
            return T.cast(
              Failure(ServiceError.validation("Start date must be on or before end date")),
              Result[Expense, ServiceError]
            )
          end

          event = Event.find(expense.event_id)
          if event&.start_date && event.end_date
            if Date.parse(sd) < event.start_date || Date.parse(ed) > event.end_date
              return T.cast(
                Failure(ServiceError.validation("Expense dates must fall within event date range")),
                Result[Expense, ServiceError]
              )
            end
          end
        end

        T.cast(Success(expense), Result[Expense, ServiceError])
      end

      sig do
        params(
          expense: Expense,
          workspace_id: T.any(String, UUID),
          description: T.nilable(String),
          amount: T.nilable(Float),
          start_date: T.nilable(String),
          end_date: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_expense(expense, workspace_id, description, amount, start_date, end_date)
        DB.transaction do
          updates = { updated_at: Time.now }
          updates[:description] = description if description && !description.empty?
          updates[:amount] = amount unless amount.nil?
          if start_date && !start_date.empty? && end_date && !end_date.empty?
            updates[:start_date] = Date.parse(start_date)
            updates[:end_date] = Date.parse(end_date)
          end
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
