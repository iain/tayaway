# typed: true
# frozen_string_literal: true

module Auth
  # Service to verify a magic link token and create a session.
  #
  # @example
  #   result = Auth::VerifyToken.call(token: "abc123", email: "user@example.com")
  #   result.success?  # => true
  #   result.value!    # => { session_token: "...", user_id: "uuid" }
  module VerifyToken
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(token: T.nilable(String), email: T.nilable(String))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(token:, email:)
        validate_params(token, email)
          .bind { |params| find_magic_token(params[:token], params[:email]) }
          .bind { |magic_token| create_session(magic_token) }
      end

      private

      sig do
        params(token: T.nilable(String), email: T.nilable(String))
          .returns(Result[T::Hash[Symbol, String], ServiceError])
      end
      def validate_params(token, email)
        if token.nil? || email.nil?
          Failure(ServiceError.validation("Token and email are required"))
        else
          Success({ token: token, email: email })
        end
      end

      sig { params(token: String, email: String).returns(Result[MagicLinkToken, ServiceError]) }
      def find_magic_token(token, email)
        magic_token = MagicLinkToken.find_valid_token(token, email)
        if magic_token
          Success(magic_token)
        else
          Failure(ServiceError.unauthorized("Invalid or expired magic link"))
        end
      end

      sig { params(magic_token: MagicLinkToken).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def create_session(magic_token)
        magic_token.mark_used!
        session = Session.create_for_user(magic_token.user)

        Success({
          session_token: session.token,
          user_id: magic_token.user.id
        })
      end
    end
  end
end
