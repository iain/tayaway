# typed: true
# frozen_string_literal: true

module Auth
  # Service to create and send a magic link for authentication.
  #
  # @example
  #   result = Auth::CreateMagicLink.call(email: "user@example.com")
  #   result.success?  # => true
  #   result.value!    # => { message: "If an account exists..." }
  module CreateMagicLink
    class << self
      extend T::Sig
      include Result::Methods

      sig { params(email: T.nilable(String)).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def call(email:)
        validate_email(email).bind { |valid_email| generate_magic_link(valid_email) }
      end

      private

      sig { params(email: T.nilable(String)).returns(Result[String, ServiceError]) }
      def validate_email(email)
        if email.nil? || email.empty?
          T.cast(Failure(ServiceError.validation("Email is required")), Result[String, ServiceError])
        else
          T.cast(Success(email), Result[String, ServiceError])
        end
      end

      sig { params(email: String).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def generate_magic_link(email)
        user = User.find_by_email(email)

        if user
          raw_token = create_magic_link_token(user.id, user.email)
          jwt = Auth::Token.encode_magic_link(token: raw_token, email: user.email.to_s)
          frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
          magic_link = "#{frontend_url}/auth/verify?token=#{jwt}"

          APP_LOGGER.debug { "MAGIC LINK FOR #{email}: #{magic_link}" }
        else
          APP_LOGGER.debug { "No user found for email #{email}" }
        end

        T.cast(Success({ message: "If an account exists with this email, a magic link has been sent." }), Result[T::Hash[Symbol, String], ServiceError])
      end

      sig { params(user_id: T.any(String, UUID), email: T.any(String, EmailAddress)).returns(String) }
      def create_magic_link_token(user_id, email)
        now = Time.now
        id = SecureRandom.uuid
        token = SecureRandom.hex(32)
        expires_at = now + (MagicLinkToken::EXPIRY_MINUTES * 60)

        DB[:magic_link_tokens].insert(
          id: id,
          user_id: user_id,
          token: Auth::Token.digest(token),
          email: email,
          expires_at: expires_at,
          created_at: now
        )

        token
      end
    end
  end
end
