# frozen_string_literal: true

module Workspaces
  # Shared validators for Workspaces services.
  module Validators
    include LengthValidation

    def validate_name(name, required: true)
      validate_length(name, max: ValidationLimits::SHORT_STRING, field: "Name", required: required)
    end

    # Blank means "use the default" (create) or "no change" (update); anything
    # else must be a known IANA identifier (see Timezones.blank_or_valid?).
    def validate_timezone(timezone)
      if Timezones.blank_or_valid?(timezone)
        Success(true)
      else
        Failure(ServiceError.validation("Unknown timezone"))
      end
    end
  end
end
