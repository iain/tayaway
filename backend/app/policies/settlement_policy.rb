# typed: true
# frozen_string_literal: true

# Policy for Settlement objects. Settlement creator or event owner can delete.
class SettlementPolicy < BasePolicy
  extend T::Sig

  class Context < T::Struct
    const :event_owner_user_id, String
  end

  sig do
    params(
      settlement: Settlement,
      user_id: String,
      context: Context,
      membership: T.nilable(WorkspaceMembership)
    ).void
  end
  def initialize(settlement:, user_id:, context:, membership: nil)
    super(user_id: user_id, membership: membership)
    @settlement = T.let(settlement, Settlement)
    @context = T.let(context, Context)
  end

  sig { override.returns(T::Hash[Symbol, Ability]) }
  def abilities
    { delete: delete_ability }
  end

  private

  sig { returns(Ability) }
  def delete_ability
    return ALLOWED if @settlement.user_id&.to_s == user_id
    return ALLOWED if @context.event_owner_user_id == user_id

    deny(reason: "not_owner")
  end
end
