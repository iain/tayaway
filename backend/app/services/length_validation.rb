# frozen_string_literal: true

# Shared free-text length validation for services. Mixed into a service's
# singleton (`include LengthValidation` inside `class << self`, like
# Events::Validators) so `validate_length` drops straight into a
# `Success().bind { ... }` chain.
#
# Returns Success(value) — the value unchanged — or a
# Failure(ServiceError.validation(...)) whose wording matches the messages
# already used across the app ("<Field> is required", "<Field> is too long
# (maximum N characters)"). Limits live in ValidationLimits.
module LengthValidation
  # - required: false (default) — a nil/blank value is fine (e.g. an optional
  #   note, or "clear this field" on update) and passes through unchanged.
  # - required: true — a nil/blank value fails with "<field> is required".
  def validate_length(value, max:, field:, required: false)
    if value.nil? || value.strip.empty?
      if required
        Failure(ServiceError.validation("#{field} is required"))
      else
        Success(value)
      end
    elsif value.length > max
      Failure(ServiceError.validation("#{field} is too long (maximum #{max} characters)"))
    else
      Success(value)
    end
  end
end
