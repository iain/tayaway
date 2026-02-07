# typed: true
# frozen_string_literal: true

# Enum for vote response types.
class VoteResponse < T::Enum
  extend T::Sig

  enums do
    Yes = new("yes")
    No = new("no")
    PreferablyNot = new("preferably_not")
  end

  sig { params(value: String).returns(T::Boolean) }
  def self.valid?(value)
    values.map(&:serialize).include?(value)
  end
end
