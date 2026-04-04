# typed: true
# frozen_string_literal: true

# Base class for all resource policies. Policies compute abilities for a
# given user + resource combination, returning a hash of ability names to
# results. Each result is { allowed: true/false, reason:, hint: }.
#
# Reason codes are machine-readable snake_case strings (e.g. "not_owner",
# "has_expenses"). The frontend maps these to display text.
#
# Hints control frontend UI treatment:
#   "hidden"   — don't render the control at all (default for denied)
#   "disabled" — render but disable, show reason as tooltip
#
# Deny-by-default: if an ability is missing from the hash, the frontend
# treats it as denied. All allowed abilities must be explicitly granted.
#
# @example
#   policy = EventPolicy.new(event: event, user_id: uid)
#   policy.abilities
#   # => { update: { allowed: true }, delete: { allowed: false, reason: "not_owner", hint: "hidden" } }
class BasePolicy
  extend T::Sig
  extend T::Helpers

  abstract!

  sig { params(user_id: String, membership: T.nilable(WorkspaceMembership)).void }
  def initialize(user_id:, membership: nil)
    @user_id = T.let(user_id, String)
    @membership = T.let(membership, T.nilable(WorkspaceMembership))
  end

  sig { abstract.returns(T::Hash[Symbol, T::Hash[Symbol, T.untyped]]) }
  def abilities; end

  # Checks a single ability and returns a Result for use in service bind chains.
  sig { params(ability_name: Symbol).returns(Result[T.untyped, ServiceError]) }
  def authorize!(ability_name)
    result = abilities[ability_name]
    if result && result[:allowed]
      T.cast(Result::Success.new(nil), Result[T.untyped, ServiceError])
    else
      reason = result&.[](:reason) || "not_allowed"
      T.cast(Result::Failure.new(ServiceError.forbidden(reason)), Result[T.untyped, ServiceError])
    end
  end

  private

  sig { returns(String) }
  attr_reader :user_id

  sig { returns(T.nilable(WorkspaceMembership)) }
  attr_reader :membership

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def allow
    { allowed: true }
  end

  sig { params(reason: String, hint: String).returns(T::Hash[Symbol, T.untyped]) }
  def deny(reason:, hint: "hidden")
    { allowed: false, reason: reason, hint: hint }
  end
end
