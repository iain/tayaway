# typed: true
# frozen_string_literal: true

# Shared string-length and value limits used across service validations.
module ValidationLimits
  extend T::Sig

  # Maximum length for short strings (names, descriptions of items, locations).
  SHORT_STRING = 255

  # Maximum length for long free-text fields (event descriptions, task content).
  LONG_TEXT = 5_000

  # Maximum length for vote comments.
  VOTE_COMMENT = 1_000

  # Maximum length for phone numbers.
  PHONE_NUMBER = 50

  # Maximum people per day for chore assignments.
  PEOPLE_PER_DAY_MAX = 50

  # Maximum expense amount in euros.
  EXPENSE_AMOUNT_MAX = 1_000_000

  # Hard limit on list query results to prevent unbounded queries.
  QUERY_LIMIT = 500

  # Valid latitude range (-90 to 90).
  LATITUDE_RANGE = T.let((-90.0..90.0), T::Range[Float])

  # Valid longitude range (-180 to 180).
  LONGITUDE_RANGE = T.let((-180.0..180.0), T::Range[Float])

  # Reasonable birthday range.
  BIRTHDAY_MIN = T.let(Date.new(1900, 1, 1), Date)

  # Parses a coordinate value strictly, returning nil for blank/invalid input.
  # Accepts both numeric types (from JSON) and strings (from form data).
  # Uses Float() instead of to_f to reject non-numeric strings like "abc".
  sig { params(value: T.untyped).returns(T.nilable(Float)) }
  def self.parse_coordinate(value)
    return nil if value.nil?
    return value.to_f if value.is_a?(Numeric)

    str = value.to_s.strip
    return nil if str.empty?

    Float(str)
  rescue ArgumentError, TypeError
    nil
  end
end
