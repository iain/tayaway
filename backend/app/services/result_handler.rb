# frozen_string_literal: true

# Mixin module for Roda routes to handle Result monad responses.
#
# Include this module in the App class to get access to helper methods
# for converting Result monads into HTTP responses.
#
# @example In a route
#   r.post do
#     result = Auth::CreateLoginLink.call(email: r.params["email"])
#     handle_result(result)
#   end
module ResultHandler
  # Handle a Result monad and convert it to an HTTP response.
  #
  # For Success results, sets the appropriate HTTP status and returns the success value.
  # For Failure results with ServiceError, sets the error status and returns the error hash.
  #
  # @param result [Result] The Result monad to handle
  # @param success_status [Integer] HTTP status code for successful responses (default: 200)
  # @return [Hash] The response body to be serialized as JSON
  def handle_result(result, success_status: 200)
    result.either(
      ->(value) {
        self.response.status = success_status
        value
      },
      ->(error) {
        self.response.status = error.http_status
        error.to_api_hash
      }
    )
  end
end
