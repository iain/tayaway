# typed: true
# frozen_string_literal: true

# A typed error struct for service failures with HTTP status code mapping.
#
# @example Creating a validation error
#   ServiceError.validation("Email is required")  # => ServiceError with status 400
#
# @example Creating a not found error
#   ServiceError.not_found("Event not found")  # => ServiceError with status 404
class ServiceError < T::Struct
  extend T::Sig

  # Error code symbol that maps to HTTP status
  const :code, Symbol

  # Human-readable error message
  const :message, String

  # Maps error codes to HTTP status codes
  HTTP_STATUS_MAP = T.let(
    {
      validation_error: 400,
      unauthorized: 401,
      forbidden: 403,
      not_found: 404,
      conflict: 409
    }.freeze, T::Hash[Symbol, Integer]
  )

  sig { returns(Integer) }
  def http_status
    HTTP_STATUS_MAP.fetch(code, 500)
  end

  sig { returns(T::Hash[Symbol, String]) }
  def to_api_hash
    { error: message }
  end

  class << self
    extend T::Sig

    sig { params(message: String).returns(ServiceError) }
    def validation(message)
      new(code: :validation_error, message: message)
    end

    sig { params(message: String).returns(ServiceError) }
    def not_found(message)
      new(code: :not_found, message: message)
    end

    sig { params(message: String).returns(ServiceError) }
    def unauthorized(message)
      new(code: :unauthorized, message: message)
    end

    sig { params(message: String).returns(ServiceError) }
    def forbidden(message)
      new(code: :forbidden, message: message)
    end

    sig { params(message: String).returns(ServiceError) }
    def conflict(message)
      new(code: :conflict, message: message)
    end
  end
end
