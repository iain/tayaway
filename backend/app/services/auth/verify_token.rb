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
      def call(token:, ip: nil, user_agent: nil)
        decode_jwt(token)
          .bind { |params| claim_magic_token(params[:token], params[:email]) }
          .bind { |user_id| create_session(user_id, ip: ip, user_agent: user_agent) }
      end

      private

      def decode_jwt(jwt)
        if jwt.nil?
          return Failure(ServiceError.validation("Token is required"))
        end

        decoded = Auth::Token.decode_login_link(jwt)
        Success(decoded)
      rescue JWT::DecodeError => e
        APP_LOGGER.warn { "[Auth] Login link verification failed: #{e.class}" }
        Failure(ServiceError.unauthorized("Invalid or expired login link"))
      end

      def claim_magic_token(token, email)
        digest = Auth::Token.digest(token)
        row = DB[:login_link_tokens]
              .where(token: digest, email: email, used_at: nil)
              .where(Sequel[:expires_at] > Time.now)
              .returning(:id, :user_id, :email)
              .update(used_at: Time.now)
              .first

        unless row
          return Failure(ServiceError.unauthorized("Invalid or expired login link"))
        end

        user = User.find(row[:user_id])
        unless user && user.email.to_s.downcase == email.downcase
          return Failure(ServiceError.unauthorized("Invalid or expired login link"))
        end

        Success(row[:user_id].to_s)
      end

      def create_session(user_id, ip: nil, user_agent: nil)
        result = Auth::SessionCreator.create(user_id, ip: ip, user_agent: user_agent)
        APP_LOGGER.info { "[Auth::VerifyToken] Session created for user #{user_id}" }
        Success(result)
      end
    end
  end
end
