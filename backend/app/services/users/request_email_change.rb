# typed: true
# frozen_string_literal: true

module Users
  # Service to request an email change. Sends a verification link to the new address.
  module RequestEmailChange
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          user_id: T.any(String, UUID),
          new_email: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, String], ServiceError])
      end
      def call(user_id:, new_email:)
        find_user(user_id)
          .bind { |user| parse_email(new_email, user) }
          .bind { |user, parsed_email| check_not_same(user, parsed_email) }
          .bind { |user, parsed_email| check_not_taken(user, parsed_email) }
          .bind { |user, parsed_email| create_and_send(user, parsed_email) }
      end

      private

      sig { params(user_id: T.any(String, UUID)).returns(Result[User, ServiceError]) }
      def find_user(user_id)
        user = User.find(user_id)
        if user
          T.cast(Success(user), Result[User, ServiceError])
        else
          T.cast(Failure(ServiceError.not_found("User not found")), Result[User, ServiceError])
        end
      end

      sig do
        params(new_email: T.nilable(String), user: User)
          .returns(Result[T::Array[T.untyped], ServiceError])
      end
      def parse_email(new_email, user)
        T.cast(
          EmailAddress.parse(new_email).fmap { |parsed| [user, parsed] },
          Result[T::Array[T.untyped], ServiceError]
        )
      end

      sig do
        params(user: User, parsed_email: EmailAddress)
          .returns(Result[T::Array[T.untyped], ServiceError])
      end
      def check_not_same(user, parsed_email)
        if user.email.downcase == parsed_email.downcase
          T.cast(
            Failure(ServiceError.validation("New email must be different from your current email")),
            Result[T::Array[T.untyped], ServiceError]
          )
        else
          T.cast(Success([user, parsed_email]), Result[T::Array[T.untyped], ServiceError])
        end
      end

      sig do
        params(user: User, parsed_email: EmailAddress)
          .returns(Result[T::Array[T.untyped], ServiceError])
      end
      def check_not_taken(user, parsed_email)
        existing = User.find_by_email(parsed_email)
        if existing
          T.cast(
            Failure(ServiceError.validation("This email is already in use")),
            Result[T::Array[T.untyped], ServiceError]
          )
        else
          T.cast(Success([user, parsed_email]), Result[T::Array[T.untyped], ServiceError])
        end
      end

      sig do
        params(user: User, parsed_email: EmailAddress)
          .returns(Result[T::Hash[Symbol, String], ServiceError])
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

        T.cast(
          Success({ message: "A verification link has been sent to #{parsed_email}. Please check your inbox." }),
          Result[T::Hash[Symbol, String], ServiceError]
        )
      end
    end
  end
end
