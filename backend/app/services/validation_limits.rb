# frozen_string_literal: true

# Shared string-length and value limits used across service validations.
module ValidationLimits
  # Maximum length for short strings (names, descriptions of items, locations).
  SHORT_STRING = 255

  # Maximum length for medium one-line free text (task item content, chore
  # notes). Kept short so list rows stay readable and can't be flooded.
  MEDIUM_TEXT = 500

  # Maximum length for long free-text fields (event descriptions).
  LONG_TEXT = 5_000

  # Maximum length for vote comments.
  VOTE_COMMENT = 1_000

  # Maximum length for phone numbers.
  PHONE_NUMBER = 50

  # Maximum people per day for chore assignments.
  PEOPLE_PER_DAY_MAX = 50

  # Maximum guests ("+N") an attendee may bring on a single day. Bounded to keep
  # a day's head count — and thus one person's expense share — sane.
  PLUS_ONES_PER_DAY_MAX = 20

  # Maximum expense amount in euros.
  EXPENSE_AMOUNT_MAX = 1_000_000

  # Maximum number of explicit participants on a single expense. Bounded because
  # each entry becomes a row insert and a broadcast notification.
  PARTICIPANT_MAX = 100

  # Hard limit on list query results to prevent unbounded queries.
  QUERY_LIMIT = 500

  # Valid latitude range (-90 to 90).
  LATITUDE_RANGE = (-90.0..90.0)

  # Valid longitude range (-180 to 180).
  LONGITUDE_RANGE = (-180.0..180.0)

  # Reasonable birthday range.
  BIRTHDAY_MIN = Date.new(1900, 1, 1)

  # Parses a coordinate value strictly, returning nil for blank/invalid input.
  # Accepts both numeric types (from JSON) and strings (from form data).
  # Uses Float() instead of to_f to reject non-numeric strings like "abc".
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
