# typed: true
# frozen_string_literal: true

module Expenses
  # Shared validators for Expenses services.
  module Validators
    extend T::Sig
    include Result::Methods

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
      params(expense: Expense, current_user_id: T.any(String, UUID), action: String)
        .returns(Result[Expense, ServiceError])
    end
    def check_owner(expense, current_user_id, action: "update")
      if expense.user_id&.to_s == current_user_id.to_s
        T.cast(Success(expense), Result[Expense, ServiceError])
      else
        T.cast(Failure(ServiceError.forbidden("Not authorized to #{action} this expense")), Result[Expense, ServiceError])
      end
    end
  end
end
