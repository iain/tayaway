# typed: true
# frozen_string_literal: true

module Users
  # Service to verify an email change token and update the user's email.
  module VerifyEmailChange
    class << self
      extend T::Sig
      include Result::Methods

      sig { params(token: T.nilable(String)).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def call(token:)
        decode_jwt(token)
          .bind { |params| find_token(T.must(params[:token]), T.must(params[:email])) }
          .bind { |email_token| validate_not_taken(email_token) }
          .bind { |email_token| validate_email_unchanged(email_token) }
          .bind { |email_token| update_email(email_token) }
      end

      private

      sig { params(jwt: T.nilable(String)).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def decode_jwt(jwt)
        if jwt.nil?
          return T.cast(
            Failure(ServiceError.validation("Token is required")),
            Result[T::Hash[Symbol, String], ServiceError]
          )
        end

        decoded = Auth::Token.decode_email_change(jwt)
        T.cast(Success(decoded), Result[T::Hash[Symbol, String], ServiceError])
      rescue JWT::DecodeError
        T.cast(
          Failure(ServiceError.unauthorized("Invalid or expired verification link")),
          Result[T::Hash[Symbol, String], ServiceError]
        )
      end

      sig { params(token: String, new_email: String).returns(Result[EmailChangeToken, ServiceError]) }
      def find_token(token, new_email)
        email_token = EmailChangeToken.find_valid(token, new_email)
        if email_token
          T.cast(Success(email_token), Result[EmailChangeToken, ServiceError])
        else
          T.cast(
            Failure(ServiceError.unauthorized("Invalid or expired verification link")),
            Result[EmailChangeToken, ServiceError]
          )
        end
      end

      sig { params(email_token: EmailChangeToken).returns(Result[EmailChangeToken, ServiceError]) }
      def validate_not_taken(email_token)
        existing = User.find_by_email(email_token.new_email)
        if existing
          T.cast(
            Failure(ServiceError.validation("This email is already in use by another account")),
            Result[EmailChangeToken, ServiceError]
          )
        else
          T.cast(Success(email_token), Result[EmailChangeToken, ServiceError])
        end
      end

      sig { params(email_token: EmailChangeToken).returns(Result[EmailChangeToken, ServiceError]) }
      def validate_email_unchanged(email_token)
        user = User.find(email_token.user_id)
        if user && user.email.downcase == email_token.email.downcase
          T.cast(Success(email_token), Result[EmailChangeToken, ServiceError])
        else
          T.cast(
            Failure(ServiceError.validation("Your email has already been changed. Please request a new verification link.")),
            Result[EmailChangeToken, ServiceError]
          )
        end
      end

      sig { params(email_token: EmailChangeToken).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def update_email(email_token)
        DB.transaction do
          DB[:email_change_tokens].where(id: email_token.id.to_s).update(used_at: Time.now)

          DB[:users].where(id: email_token.user_id.to_s).update(
            email: email_token.new_email.to_s,
            updated_at: Time.now
          )

          # Invalidate all sessions, pending magic links, and WS tickets
          DB[:sessions].where(user_id: email_token.user_id.to_s).delete
          DB[:magic_link_tokens].where(user_id: email_token.user_id.to_s, used_at: nil).update(used_at: Time.now)
          DB[:ws_tickets].where(user_id: email_token.user_id.to_s, used_at: nil).update(used_at: Time.now)

          # Broadcast member changes to all workspaces the user belongs to
          WorkspaceMembership.for_user(email_token.user_id).each do |m|
            Broadcaster.object_changed("member", m.id, workspace_id: m.workspace_id)
          end
        end

        APP_LOGGER.info { "[Users::VerifyEmailChange] User #{email_token.user_id} changed email from #{email_token.email} to #{email_token.new_email}" }
        T.cast(
          Success({ message: "Your email has been updated successfully." }),
          Result[T::Hash[Symbol, String], ServiceError]
        )
      end
    end
  end
end
