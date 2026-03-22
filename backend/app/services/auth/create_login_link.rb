# typed: true
# frozen_string_literal: true

module Auth
  # Service to create and send a login link for authentication.
  #
  # @example
  #   result = Auth::CreateLoginLink.call(email: "user@example.com")
  #   result.success?  # => true
  #   result.value!    # => { message: "If an account exists..." }
  module CreateLoginLink
    class << self
      extend T::Sig
      include Result::Methods

      sig { params(email: T.nilable(String)).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def call(email:)
        validate_email(email).bind { |valid_email| generate_login_link(valid_email) }
      end

      # Create a login link token, build the login URL, and send the email.
      # Shared by Auth::CreateLoginLink and Invites::Accept.
      sig { params(user: User).void }
      def send_login_link(user)
        raw_token = create_token(user.id, user.email)
        jwt = Auth::Token.encode_login_link(token: raw_token, email: user.email.to_s)
        frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
        login_link = "#{frontend_url}/auth/verify?token=#{jwt}"

        workspaces = Workspace.for_user(user.id)
        workspace_name = workspaces.length == 1 ? T.must(workspaces.first).name : "Tayaway"

        email = user.email.to_s

        APP_LOGGER.info { "[Auth::CreateLoginLink] Sending login link for user #{user.id}" }
        APP_LOGGER.info { "[Auth::CreateLoginLink] LOGIN LINK FOR #{email}: #{login_link}" } if APP_ENV == "development"
        Mailers::LoginLink.send_email(email: email, login_link: login_link, workspace_name: workspace_name)
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
      def generate_login_link(email)
        user = User.find_by_email(email)

        if user
          send_login_link(user)
        else
          APP_LOGGER.info { "[Auth::CreateLoginLink] Login link requested for unknown email" }
        end

        T.cast(Success({ message: "If an account exists with this email, a login link has been sent." }), Result[T::Hash[Symbol, String], ServiceError])
      end

      sig { params(user_id: T.any(String, UUID), email: T.any(String, EmailAddress)).returns(String) }
      def create_token(user_id, email)
        DB[:login_link_tokens].where(user_id: user_id.to_s, used_at: nil).update(used_at: Time.now)

        now = Time.now
        id = SecureRandom.uuid
        token = SecureRandom.hex(32)
        expires_at = now + (LoginLinkToken::EXPIRY_MINUTES * 60)

        DB[:login_link_tokens].insert(
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
