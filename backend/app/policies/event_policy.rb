# typed: true
# frozen_string_literal: true

# Policy for Event objects. Computes abilities based on ownership.
#
# Context fields (set via `with_context`):
#   has_expenses:   whether the event has any expenses
#   has_settlements: whether the event has any settlements
#
# @example
#   policy = EventPolicy.new(event: event, user_id: uid)
#   policy.with_context(has_expenses: true, has_settlements: false)
#   policy.abilities
class EventPolicy < BasePolicy
  extend T::Sig

  sig { params(event: Event, user_id: String, membership: T.nilable(WorkspaceMembership)).void }
  def initialize(event:, user_id:, membership: nil)
    super(user_id: user_id, membership: membership)
    @event = T.let(event, Event)
    @has_expenses = T.let(false, T::Boolean)
    @has_settlements = T.let(false, T::Boolean)
  end

  sig { params(has_expenses: T::Boolean, has_settlements: T::Boolean).returns(EventPolicy) }
  def with_context(has_expenses: false, has_settlements: false)
    @has_expenses = has_expenses
    @has_settlements = has_settlements
    self
  end

  sig { override.returns(T::Hash[Symbol, T::Hash[Symbol, T.untyped]]) }
  def abilities
    {
      update: owner_ability,
      delete: delete_ability,
      create_poll: owner_ability,
      close_poll: owner_ability,
      reopen_poll: owner_ability,
      add_date_range: owner_ability,
      remove_date_range: owner_ability
    }
  end

  private

  sig { returns(T::Boolean) }
  def owner?
    @event.user_id.to_s == user_id
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def owner_ability
    owner? ? allow : deny(reason: "not_owner")
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def delete_ability
    return deny(reason: "not_owner") unless owner?
    return deny(reason: "has_settlements", hint: "disabled") if @has_settlements
    return deny(reason: "has_expenses", hint: "disabled") if @has_expenses

    allow
  end
end
