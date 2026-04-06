# frozen_string_literal: true

# A typed error struct for service failures with HTTP status code mapping.
#
# @example Creating a validation error
#   ServiceError.validation("Email is required")  # => ServiceError with status 400
#
# @example Creating a not found error
#   ServiceError.not_found("Event not found")  # => ServiceError with status 404
class ServiceError
  attr_reader :code, :message

  def initialize(code:, message:)
    @code = code
    @message = message
  end

  # Maps error codes to HTTP status codes
  HTTP_STATUS_MAP = {
    validation_error: 400,
      unauthorized: 401,
      forbidden: 403,
      not_found: 404,
      conflict: 409,
      gone: 410
  }.freeze

  def http_status
    HTTP_STATUS_MAP.fetch(code, 500)
  end

  def to_api_hash
    { error: message }
  end

  class << self
    def validation(message)
      new(code: :validation_error, message: message)
    end

    def not_found(message)
      new(code: :not_found, message: message)
    end

    def unauthorized(message)
      new(code: :unauthorized, message: message)
    end

    def forbidden(message)
      new(code: :forbidden, message: message)
    end

    def conflict(message)
      new(code: :conflict, message: message)
    end

    def gone(message)
      new(code: :gone, message: message)
    end
  end
end
