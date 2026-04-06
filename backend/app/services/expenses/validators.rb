# frozen_string_literal: true

module Expenses
  # Shared validators for Expenses services.
  module Validators
    include Result::Methods

    def check_not_settled(expense)
      if expense.settlement_id
        Failure(ServiceError.validation("Expense is part of a settlement. Delete the settlement first to edit."))
      else
        Success(expense)
      end
    end

    def check_owner(expense, current_user_id, action: "update")
      if expense.user_id&.to_s == current_user_id.to_s
        Success(expense)
      else
        Failure(ServiceError.forbidden("Not authorized to #{action} this expense"))
      end
    end
  end
end
