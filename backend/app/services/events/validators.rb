# frozen_string_literal: true

module Events
  # Shared validators for Events services.
  module Validators
    include LengthValidation

    def validate_text_lengths(description, location_name)
      validate_length(description, max: ValidationLimits::LONG_TEXT, field: "Description")
        .bind { validate_length(location_name, max: ValidationLimits::SHORT_STRING, field: "Location name") }
        .fmap { true }
    end

    def validate_coordinates(latitude, longitude)
      if latitude && !ValidationLimits::LATITUDE_RANGE.cover?(latitude)
        return Failure(ServiceError.validation("Latitude must be between -90 and 90"))
      end

      if longitude && !ValidationLimits::LONGITUDE_RANGE.cover?(longitude)
        return Failure(ServiceError.validation("Longitude must be between -180 and 180"))
      end

      Success(true)
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
