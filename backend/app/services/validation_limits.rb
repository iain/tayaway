# typed: true
# frozen_string_literal: true

# Shared string-length and value limits used across service validations.
module ValidationLimits
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
end
