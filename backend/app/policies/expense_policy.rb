# frozen_string_literal: true

class ExpensePolicy
  include Policy

  ACTIONS = %i[edit delete revert].freeze

  # `event` and `membership` are only consulted by `revert`. `edit` and
  # `delete` are pure invariant checks; the actor's workspace membership is
  # already established at the route layer.
  def initialize(expense, membership: nil, event: nil, **)
    @settled = !expense.settlement_id.nil?
    @is_revert = !expense.reverts_expense_id.nil?
    @subject = expense.user_id
    @creator = expense.created_by_user_id
    @membership = membership
    @event = event
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
  #
  # Authority is narrower than edit/delete because reverts have lasting
  # ledger effects: the expense's owner, whoever filed it, the event owner,
  # or a workspace admin/owner. We deliberately raise rather than silently
  # closing the event-owner path when the caller forgets to pass `event:` —
  # missing context here is a programming error, not "not authorised".
  def revert
    raise ArgumentError, "ExpensePolicy#revert needs membership: context" if @membership.nil?
    raise ArgumentError, "ExpensePolicy#revert needs event: context" if @event.nil?

    if @is_revert
      Failure(:revert_of_revert)
    elsif !@settled
      Failure(:not_settled)
    elsif authorized_to_revert?
      Success()
    else
      Failure(:not_revert_authority)
    end
  end

  private

  def authorized_to_revert?
    actor_id = @membership.user_id
    actor_id == @subject ||
      actor_id == @creator ||
      @event.user_id == actor_id ||
      %w[admin owner].include?(@membership.role)
  end
end
