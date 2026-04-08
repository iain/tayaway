# frozen_string_literal: true

# Base module for all policy classes. Each policy declares an ACTIONS constant
# listing its permission methods. Each method returns Success() or Failure(:reason).
#
# @example
#   class EventPolicy
#     include Policy
#     ACTIONS = %i[edit delete].freeze
#
#     def edit
#       if @owner then Success() else Failure(:not_owner) end
#     end
#   end
#
#   EventPolicy.new(event, membership: m).permissions
#   # => { edit: { allowed: true }, delete: { allowed: false, reason: "not_owner" } }
module Policy
  include Dry::Monads[:result]

  def permissions
    self.class::ACTIONS.each_with_object({}) do |action, hash|
      hash[action] = to_permission(send(action))
    end
  end

  private

  def to_permission(result)
    case result
    in Success
      { allowed: true }
    in Failure(reason)
      { allowed: false, reason: reason.to_s }
    end
  end
end
