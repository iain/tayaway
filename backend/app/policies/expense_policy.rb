# frozen_string_literal: true

class ExpensePolicy
  include Policy

  ACTIONS = %i[edit delete].freeze

  def initialize(expense, membership:, **)
    @expense = expense
    @creator = expense.user_id == membership.user_id
    @settled = !expense.settlement_id.nil?
  end

  def edit = require_unsettled_creator

  def delete = require_unsettled_creator

  private

  def require_unsettled_creator
    if @settled
      Failure(:settled)
    elsif @creator
      Success()
    else
      Failure(:not_creator)
    end
  end
end
