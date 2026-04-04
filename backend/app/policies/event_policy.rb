# typed: true
# frozen_string_literal: true

# Policy for Event objects. Computes abilities based on ownership and
# pre-computed context about related data.
#
# @example
#   context = EventPolicy::Context.new(has_expenses: true, has_settlements: false)
#   policy = EventPolicy.new(event: event, user_id: uid, context: context)
#   policy.abilities[:delete]         # => Denied(reason: "has_expenses", hint: Disabled)
#   policy.abilities[:update]         # => Allowed
class EventPolicy < BasePolicy
  extend T::Sig

  # Pre-computed facts about the event's related data, passed in at construction.
  class Context < T::Struct
    const :has_expenses, T::Boolean, default: false
    const :has_settlements, T::Boolean, default: false
  end

  sig do
    params(
      event: Event,
      user_id: String,
      membership: T.nilable(WorkspaceMembership),
      context: Context
    ).void
  end
  def initialize(event:, user_id:, membership: nil, context: Context.new)
    super(user_id: user_id, membership: membership)
    @event = T.let(event, Event)
    @context = T.let(context, Context)
  end

  sig { override.returns(T::Hash[Symbol, Ability]) }
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

  sig { returns(Ability) }
  def owner_ability
    owner? ? ALLOWED : deny(reason: "not_owner")
  end

  sig { returns(Ability) }
  def delete_ability
    return deny(reason: "not_owner") unless owner?
    return deny(reason: "has_settlements") if @context.has_settlements
    return deny(reason: "has_expenses") if @context.has_expenses

    ALLOWED
  end
end
