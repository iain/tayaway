# typed: true
# frozen_string_literal: true

# Policy for ChoreRoster objects. Only the creator can delete.
class ChoreRosterPolicy < BasePolicy
  extend T::Sig

  sig { params(roster: ChoreRoster, user_id: String, membership: T.nilable(WorkspaceMembership)).void }
  def initialize(roster:, user_id:, membership: nil)
    super(user_id: user_id, membership: membership)
    @roster = T.let(roster, ChoreRoster)
  end

  sig { override.returns(T::Hash[Symbol, Ability]) }
  def abilities
    { delete: delete_ability }
  end

  private

  sig { returns(Ability) }
  def delete_ability
    @roster.user_id&.to_s == user_id ? ALLOWED : deny(reason: "not_creator")
  end
end
