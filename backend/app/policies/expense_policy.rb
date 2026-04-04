# typed: true
# frozen_string_literal: true

# Policy for Expense objects. Both update and delete share the same logic:
# must be the creator, and the expense must not be part of a settlement.
class ExpensePolicy < BasePolicy
  extend T::Sig

  sig { params(expense: Expense, user_id: String, membership: T.nilable(WorkspaceMembership)).void }
  def initialize(expense:, user_id:, membership: nil)
    super(user_id: user_id, membership: membership)
    @expense = T.let(expense, Expense)
  end

  sig { override.returns(T::Hash[Symbol, Ability]) }
  def abilities
    result = mutate_ability
    { update: result, delete: result }
  end

  private

  sig { returns(Ability) }
  def mutate_ability
    return deny(reason: "not_owner") unless @expense.user_id&.to_s == user_id
    return deny(reason: "is_settled") if @expense.settlement_id

    ALLOWED
  end
end
