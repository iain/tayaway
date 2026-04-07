# frozen_string_literal: true

module Users
  # Service to verify an email change token and update the user's email.
  module VerifyEmailChange
    class << self
      include Dry::Monads[:result]

      def call(token:)
        decode_jwt(token)
          .bind { |params| find_token(params[:token], params[:email]) }
          .bind { |email_token| validate_not_taken(email_token) }
          .bind { |email_token| validate_email_unchanged(email_token) }
          .bind { |email_token| update_email(email_token) }
      end

      private

      def decode_jwt(jwt)
        if jwt.nil?
          return Failure(ServiceError.validation("Token is required"))
        end

        decoded = Auth::Token.decode_email_change(jwt)
        Success(decoded)
      rescue JWT::DecodeError
        Failure(ServiceError.unauthorized("Invalid or expired verification link"))
      end

      def find_token(token, new_email)
        email_token = EmailChangeToken.find_valid(token, new_email)
        if email_token
          Success(email_token)
        else
          Failure(ServiceError.unauthorized("Invalid or expired verification link"))
        end
      end

      def validate_not_taken(email_token)
        existing = User.find_by_email(email_token.new_email)
        if existing
          Failure(ServiceError.validation("This email is already in use by another account"))
        else
          Success(email_token)
        end
      end

      def validate_email_unchanged(email_token)
        user = User.find(email_token.user_id)
        if user && user.email.downcase == email_token.email.downcase
          Success(email_token)
        else
          Failure(ServiceError.validation("Your email has already been changed. Please request a new verification link."))
        end
      end

      def update_email(email_token)
        DB.transaction do
          DB[:email_change_tokens].where(id: email_token.id.to_s).update(used_at: Time.now)

          DB[:users].where(id: email_token.user_id.to_s).update(
            email: email_token.new_email.to_s,
            updated_at: Time.now
          )

          # Invalidate all sessions and pending login links.
          # ws_tickets are cascade-deleted when their session is deleted.
          DB[:sessions].where(user_id: email_token.user_id.to_s).delete
          DB[:login_link_tokens].where(user_id: email_token.user_id.to_s, used_at: nil).update(used_at: Time.now)

          # Broadcast member changes to all workspaces the user belongs to
          WorkspaceMembership.for_user(email_token.user_id).each do |m|
            Broadcaster.object_changed("member", m.id, workspace_id: m.workspace_id)
          end
        end

        APP_LOGGER.info { "[Users::VerifyEmailChange] User #{email_token.user_id} changed email from #{email_token.email} to #{email_token.new_email}" }
        Success({ message: "Your email has been updated successfully." })
      end
    end
  end
end
