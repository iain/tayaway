# typed: true
# frozen_string_literal: true

module Events
  # Shared validators for Events services.
  module Validators
    extend T::Sig
    include Result::Methods

    sig do
      params(
        description: T.nilable(String),
        location_name: T.nilable(String)
      ).returns(Result[TrueClass, ServiceError])
    end
    def validate_text_lengths(description, location_name)
      if description && description.length > ValidationLimits::LONG_TEXT
        return T.cast(Failure(ServiceError.validation("Description is too long (maximum 5000 characters)")), Result[TrueClass, ServiceError])
      end

      if location_name && location_name.length > ValidationLimits::SHORT_STRING
        return T.cast(Failure(ServiceError.validation("Location name is too long (maximum 255 characters)")), Result[TrueClass, ServiceError])
      end

      T.cast(Success(true), Result[TrueClass, ServiceError])
    end
  end
end
