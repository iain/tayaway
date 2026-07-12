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
      def call(email:)
        validate_email(email).bind { |valid_email| generate_login_link(valid_email) }
      end

      # Create a login link token, build the login URL, and send the email.
      # Returns the login link. Shared by Auth::CreateLoginLink and
      # Invites::Accept.
      def send_login_link(user)
        raw_token = create_token(user.id, user.email)
        jwt = Auth::Token.encode_login_link(token: raw_token, email: user.email.to_s)
        login_link = APP_CONFIG.frontend_url.path("/auth/verify", token: jwt)

        workspaces = Workspace.for_user(user.id)
        workspace_name = workspaces.length == 1 ? workspaces.first.name : "Tayaway"

        email = user.email.to_s

        APP_LOGGER.info { "[Auth::CreateLoginLink] Login link requested for user #{user.id}" }
        APP_LOGGER.info { "[Auth::CreateLoginLink] LOGIN LINK FOR #{email}: #{login_link}" } if APP_CONFIG.development?
        Mailers::LoginLink.send_email(email: email, login_link: login_link, workspace_name: workspace_name)

        login_link
      end

      private

      def validate_email(email)
        if email.nil? || email.empty?
          Failure(ServiceError.validation("Email is required"))
        else
          Success(email)
        end
      end

      def generate_login_link(email)
        user = User.find_by_email(email)
        response = { message: "If an account exists with this email, a login link has been sent." }

        if user
          login_link = send_login_link(user)
          # Dev-only escape hatch: surface the link in the response so the
          # login page can offer it directly instead of making you dig it out
          # of the server logs. Never set outside development.
          response[:loginLink] = login_link if APP_CONFIG.development?
        else
          APP_LOGGER.info { "[Auth::CreateLoginLink] Login link requested for unknown email" }
        end

        Success(response)
      end

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
