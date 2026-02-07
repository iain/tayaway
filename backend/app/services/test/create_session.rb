# typed: true
# frozen_string_literal: true

module Test
  # Service to create a test session for e2e testing.
  # This service should only be used in test/development environments.
  #
  # @example
  #   result = Test::CreateSession.call(email: "test@example.com", name: "Test User")
  #   result.success?  # => true
  #   result.value!    # => { session_token: "...", user_id: "uuid" }
  module CreateSession
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(email: T.nilable(String), name: T.nilable(String))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(email:, name:)
        validate_email(email).bind { |valid_email| find_or_create_user_and_session(valid_email, name) }
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

      sig do
        params(email: String, name: T.nilable(String))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def find_or_create_user_and_session(email, name)
        user = User.first(Sequel.lit("LOWER(email) = ?", email))
        user ||= User.create(email: email, name: name)

        user.update(name: name) if name && user.name != name

        session = Session.create_for_user(user)

        Success({
          session_token: session.token,
          user_id: user.id
        })
      end
    end
  end
end
