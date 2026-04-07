# frozen_string_literal: true

module Users
  # Service to request an email change. Sends a verification link to the new address.
  module RequestEmailChange
    class << self
      include Dry::Monads[:result]

      def call(user_id:, new_email:)
        find_user(user_id)
          .bind { |user| parse_email(new_email, user) }
          .bind { |user, parsed_email| check_not_same(user, parsed_email) }
          .bind { |user, parsed_email| check_not_taken(user, parsed_email) }
          .bind { |user, parsed_email| create_and_send(user, parsed_email) }
      end

      private

      def find_user(user_id)
        user = User.find(user_id)
        if user
          Success(user)
        else
          Failure(ServiceError.not_found("User not found"))
        end
      end

      def parse_email(new_email, user)
        EmailAddress.parse(new_email).fmap { |parsed| [user, parsed] }
      end

      def check_not_same(user, parsed_email)
        if user.email.downcase == parsed_email.downcase
          Failure(ServiceError.validation("New email must be different from your current email"))
        else
          Success([user, parsed_email])
        end
      end

      def check_not_taken(user, parsed_email)
        existing = User.find_by_email(parsed_email)
        if existing
          Failure(ServiceError.validation("This email is already in use"))
        else
          Success([user, parsed_email])
        end
      end

      def create_and_send(user, parsed_email)
        # Invalidate previous pending tokens
        DB[:email_change_tokens].where(user_id: user.id.to_s, used_at: nil).update(used_at: Time.now)

        now = Time.now
        id = SecureRandom.uuid
        raw_token = SecureRandom.hex(32)
        expires_at = now + (EmailChangeToken::EXPIRY_MINUTES * 60)

        DB[:email_change_tokens].insert(
          id: id,
          user_id: user.id.to_s,
          token: Auth::Token.digest(raw_token),
          email: user.email.to_s,
          new_email: parsed_email.to_s,
          expires_at: expires_at,
          created_at: now
        )

        jwt = Auth::Token.encode_email_change(token: raw_token, email: parsed_email.to_s)
        frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
        verification_link = "#{frontend_url}/verify-email?token=#{jwt}"

        APP_LOGGER.info { "[Users::RequestEmailChange] User #{user.id} requested email change to #{parsed_email}" }
        APP_LOGGER.info { "EMAIL CHANGE LINK FOR #{parsed_email}: #{verification_link}" } if APP_ENV == "development"
        Mailers::EmailChange.send_email(email: parsed_email, verification_link: verification_link)

        Success({ message: "A verification link has been sent to #{parsed_email}. Please check your inbox." })
      end
    end
  end
end
