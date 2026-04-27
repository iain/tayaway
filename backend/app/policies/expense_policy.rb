# frozen_string_literal: true

class ExpensePolicy
  include Policy

  ACTIONS = %i[edit delete revert].freeze

  def initialize(expense, **)
    @settled = !expense.settlement_id.nil?
    @is_revert = !expense.reverts_expense_id.nil?
  end

  # Any workspace member can edit/delete an expense on the owner's behalf.
  # The structural rules — can't touch a settled expense, can't edit a revert
  # entry — still hold regardless of who's acting.
  def edit
    if @is_revert
      Failure(:is_revert)
    elsif @settled
      Failure(:settled)
    else
      Success()
    end
  end

  def delete
    if @is_revert
      Failure(:is_revert)
    elsif @settled
      Failure(:settled)
    else
      Success()
    end
  end

  # Revert is the escape hatch for expenses that have been locked into a
  # settlement: a mirror-image entry (negated amount, same participants /
  # factors) offsets the original on the next settlement. Unsettled expenses
  # can still be edited or deleted directly, so revert isn't needed — and
  # isn't offered — there. A revert of a revert is disallowed; the ledger
  # shows both entries and a fresh expense is the right way to change your
  # mind.
  def revert
    if @is_revert
      Failure(:revert_of_revert)
    elsif !@settled
      Failure(:not_settled)
    else
      Success()
    end
  end
end
