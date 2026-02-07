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
          .bind { |params| find_magic_token(T.must(params[:token]), T.must(params[:email])) }
          .bind { |magic_token| create_session(magic_token) }
      end

      private

      sig do
        params(token: T.nilable(String), email: T.nilable(String))
          .returns(Result[T::Hash[Symbol, String], ServiceError])
      end
      def validate_params(token, email)
        if token.nil? || email.nil?
          T.cast(Failure(ServiceError.validation("Token and email are required")), Result[T::Hash[Symbol, String], ServiceError])
        else
          T.cast(Success({ token: token, email: email }), Result[T::Hash[Symbol, String], ServiceError])
        end
      end

      sig { params(token: String, email: String).returns(Result[MagicLinkToken, ServiceError]) }
      def find_magic_token(token, email)
        magic_token = MagicLinkToken.find_valid(token, email)
        if magic_token
          T.cast(Success(magic_token), Result[MagicLinkToken, ServiceError])
        else
          T.cast(Failure(ServiceError.unauthorized("Invalid or expired magic link")), Result[MagicLinkToken, ServiceError])
        end
      end

      sig { params(magic_token: MagicLinkToken).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def create_session(magic_token)
        DB[:magic_link_tokens].where(id: magic_token.id).update(used_at: Time.now)

        now = Time.now
        id = SecureRandom.uuid
        token = SecureRandom.hex(32)
        expires_at = now + (Session::EXPIRY_DAYS * 24 * 60 * 60)

        DB[:sessions].insert(
          id: id,
          user_id: magic_token.user_id,
          token: token,
          expires_at: expires_at,
          created_at: now
        )

        T.cast(
          Success(
            {
              session_token: token,
              user_id: magic_token.user_id
            }
          ), Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end
    end
  end
end
