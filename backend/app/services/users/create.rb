# typed: true
# frozen_string_literal: true

module Users
  # Service to create a new user.
  #
  # @example
  #   result = Users::Create.call(name: "John", email: "john@example.com")
  #   result.success?  # => true
  #   result.value!    # => { user: {...} }
  module Create
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(name: T.nilable(String), email: T.nilable(String))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(name:, email:)
        validate_email(email)
          .bind { |valid_email| check_email_uniqueness(valid_email) }
          .bind { |valid_email| create_user(name, valid_email) }
      end

      private

      sig { params(email: T.nilable(String)).returns(Result[String, ServiceError]) }
      def validate_email(email)
        if email.nil? || email.empty?
          Failure(ServiceError.validation("Email is required"))
        else
          Success(email)
        end
      end

      sig { params(email: String).returns(Result[String, ServiceError]) }
      def check_email_uniqueness(email)
        if User.first(email: email)
          Failure(ServiceError.validation("A user with this email already exists"))
        else
          Success(email)
        end
      end

      sig { params(name: T.nilable(String), email: String).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def create_user(name, email)
        user = User.create(
          name: name&.empty? ? nil : name,
          email: email
        )

        Success({ user: user.to_api_hash })
      end
    end
  end
end
