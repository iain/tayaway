# frozen_string_literal: true

class ExpensePolicy
  include Policy

  ACTIONS = %i[edit delete revert].freeze

  def initialize(expense, membership:, **)
    @expense = expense
    @creator = expense.user_id == membership.user_id
    @settled = !expense.settlement_id.nil?
    @already_reverted = !expense.reverts_expense_id.nil?
  end

  def edit = require_unsettled_creator

  def delete = require_unsettled_creator

  # Revert is the only operation permitted on settled expenses: the creator
  # can file a mirror-image entry (negated amount, same participants/factors)
  # that offsets the original on the next settlement. Cheaper and safer than
  # editing in place, and the back-reference lets the UI dim the reverted row.
  # A revert of a revert is disallowed — the ledger shows both entries; if
  # someone changes their mind they can add a fresh expense.
  def revert
    if @already_reverted
      Failure(:revert_of_revert)
    elsif @creator
      Success()
    else
      Failure(:not_creator)
    end
  end

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
