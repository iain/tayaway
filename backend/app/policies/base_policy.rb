# typed: true
# frozen_string_literal: true

# Base class for all resource policies. Policies compute abilities for a
# given user + resource combination, returning a hash of ability names to
# Ability values (either Allowed or Denied).
#
# Reason codes are machine-readable snake_case strings (e.g. "not_owner",
# "has_expenses"). The frontend maps these to display text and decides
# how to render denied actions (hidden vs. disabled) based on the reason.
#
# Deny-by-default: if an ability is missing from the hash, the frontend
# treats it as denied. All allowed abilities must be explicitly granted.
#
# @example
#   policy = EventPolicy.new(event: event, user_id: uid)
#   ability = policy.abilities[:delete]
#   ability.is_a?(Denied) # => true
#   ability.reason         # => "not_owner"
class BasePolicy
  extend T::Sig
  extend T::Helpers

  abstract!

  # Granted ability — the user may perform this action.
  class Allowed < T::Struct
    extend T::Sig

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_api_hash
      { allowed: true }
    end
  end

  # Denied ability — the user may not perform this action.
  class Denied < T::Struct
    extend T::Sig

    const :reason, String

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def to_api_hash
      { allowed: false, reason: reason }
    end
  end

  Ability = T.type_alias { T.any(Allowed, Denied) }

  ALLOWED = T.let(Allowed.new, Allowed)

  sig { params(user_id: String, membership: T.nilable(WorkspaceMembership)).void }
  def initialize(user_id:, membership: nil)
    @user_id = T.let(user_id, String)
    @membership = T.let(membership, T.nilable(WorkspaceMembership))
  end

  sig { abstract.returns(T::Hash[Symbol, Ability]) }
  def abilities; end

  # Serializes abilities for inclusion in pool object hashes.
  sig { returns(T::Hash[Symbol, T::Hash[Symbol, T.untyped]]) }
  def abilities_api_hash
    abilities.transform_values(&:to_api_hash)
  end

  # Checks a single ability and returns a Result for use in service bind chains.
  sig { params(ability_name: Symbol).returns(Result[T.untyped, ServiceError]) }
  def authorize!(ability_name)
    ability = abilities[ability_name]
    case ability
    when Allowed
      T.cast(Result::Success.new(nil), Result[T.untyped, ServiceError])
    when Denied
      T.cast(Result::Failure.new(ServiceError.forbidden(ability.reason)), Result[T.untyped, ServiceError])
    else
      T.cast(Result::Failure.new(ServiceError.forbidden("not_allowed")), Result[T.untyped, ServiceError])
    end
  end

  private

  sig { returns(String) }
  attr_reader :user_id

  sig { returns(T.nilable(WorkspaceMembership)) }
  attr_reader :membership

  sig { params(reason: String).returns(Denied) }
  def deny(reason:)
    Denied.new(reason: reason)
  end
end
