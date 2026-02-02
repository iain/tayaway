# typed: true
# frozen_string_literal: true

module Auth
  # Service to logout a user by destroying their session.
  #
  # @example
  #   result = Auth::Logout.call(auth_header: "Bearer abc123")
  #   result.success?  # => true
  #   result.value!    # => { message: "Logged out successfully" }
  module Logout
    class << self
      extend T::Sig
      include Result::Methods

      sig { params(auth_header: T.nilable(String)).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def call(auth_header:)
        validate_auth_header(auth_header).bind { |token| destroy_session(token) }
      end

      private

      sig { params(auth_header: T.nilable(String)).returns(Result[String, ServiceError]) }
      def validate_auth_header(auth_header)
        if auth_header.nil? || auth_header.empty?
          Failure(ServiceError.unauthorized("Authorization required"))
        else
          Success(auth_header.sub(/^Bearer\s+/, ""))
        end
      end

      sig { params(token: String).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def destroy_session(token)
        session = Session.first(token: token)
        session&.destroy
        Success({ message: "Logged out successfully" })
      end
    end
  end
end
