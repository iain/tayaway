# typed: true
# frozen_string_literal: true

module Auth
  # Service to verify a login link token and create a session.
  #
  # @example
  #   result = Auth::VerifyToken.call(token: "<jwt>")
  #   result.success?  # => true
  #   result.value!    # => { session_token: "...", user_id: "uuid" }
  module VerifyToken
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(token: T.nilable(String), ip: T.nilable(String), user_agent: T.nilable(String))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(token:, ip: nil, user_agent: nil)
        decode_jwt(token)
          .bind { |params| claim_magic_token(T.must(params[:token]), T.must(params[:email])) }
          .bind { |user_id| create_session(user_id, ip: ip, user_agent: user_agent) }
      end

      private

      sig do
        params(jwt: T.nilable(String))
          .returns(Result[T::Hash[Symbol, String], ServiceError])
      end
      def decode_jwt(jwt)
        if jwt.nil?
          return T.cast(Failure(ServiceError.validation("Token is required")), Result[T::Hash[Symbol, String], ServiceError])
        end

        decoded = Auth::Token.decode_login_link(jwt)
        T.cast(Success(decoded), Result[T::Hash[Symbol, String], ServiceError])
      rescue JWT::DecodeError => e
        APP_LOGGER.warn { "[Auth] Login link verification failed: #{e.class}" }
        T.cast(Failure(ServiceError.unauthorized("Invalid or expired login link")), Result[T::Hash[Symbol, String], ServiceError])
      end

      sig { params(token: String, email: String).returns(Result[String, ServiceError]) }
      def claim_magic_token(token, email)
        digest = Auth::Token.digest(token)
        row = DB[:login_link_tokens]
              .where(token: digest, email: email, used_at: nil)
              .where(Sequel[:expires_at] > Time.now)
              .returning(:id, :user_id, :email)
              .update(used_at: Time.now)
              .first

        unless row
          return T.cast(Failure(ServiceError.unauthorized("Invalid or expired login link")), Result[String, ServiceError])
        end

        user = User.find(row[:user_id])
        unless user && user.email.to_s.downcase == email.downcase
          return T.cast(Failure(ServiceError.unauthorized("Invalid or expired login link")), Result[String, ServiceError])
        end

        T.cast(Success(row[:user_id].to_s), Result[String, ServiceError])
      end

      sig do
        params(user_id: String, ip: T.nilable(String), user_agent: T.nilable(String))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_session(user_id, ip: nil, user_agent: nil)
        result = Auth::SessionCreator.create(user_id, ip: ip, user_agent: user_agent)
        APP_LOGGER.info { "[Auth::VerifyToken] Session created for user #{user_id}" }
        T.cast(Success(result), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
