# typed: true
# frozen_string_literal: true

# Policy for SettlementTransfer objects. Only the recipient can mark as paid.
class SettlementTransferPolicy < BasePolicy
  extend T::Sig

  sig { params(transfer: SettlementTransfer, user_id: String, membership: T.nilable(WorkspaceMembership)).void }
  def initialize(transfer:, user_id:, membership: nil)
    super(user_id: user_id, membership: membership)
    @transfer = T.let(transfer, SettlementTransfer)
  end

  sig { override.returns(T::Hash[Symbol, Ability]) }
  def abilities
    { mark_paid: mark_paid_ability }
  end

  private

  sig { returns(Ability) }
  def mark_paid_ability
    @transfer.to_user_id&.to_s == user_id ? ALLOWED : deny(reason: "not_recipient")
  end
end
