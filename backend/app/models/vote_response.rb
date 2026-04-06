# frozen_string_literal: true

# Enum for vote response types.
module VoteResponse
  YES = "yes"
  NO = "no"
  PREFERABLY_NOT = "preferably_not"

  VALUES = [YES, NO, PREFERABLY_NOT].freeze

  def self.valid?(value)
    VALUES.include?(value)
  end
end
