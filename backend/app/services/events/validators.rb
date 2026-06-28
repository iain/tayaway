# frozen_string_literal: true

module Events
  # Shared validators for Events services.
  module Validators
    def validate_text_lengths(description, location_name)
      if description && description.length > ValidationLimits::LONG_TEXT
        return Failure(ServiceError.validation("Description is too long (maximum 5000 characters)"))
      end

      if location_name && location_name.length > ValidationLimits::SHORT_STRING
        return Failure(ServiceError.validation("Location name is too long (maximum 255 characters)"))
      end

      Success(true)
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

    # A blank timezone means "use the default" (create) or "no change"
    # (update); anything else must be a known IANA identifier.
    def validate_timezone(timezone)
      if timezone.nil? || timezone.empty? || Timezones.valid?(timezone)
        Success(true)
      else
        Failure(ServiceError.validation("Unknown timezone"))
      end
    end
  end
end
