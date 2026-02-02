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
          Failure(ServiceError.validation("Email is required"))
        else
          Success(email)
        end
      end

      sig { params(email: String).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def generate_magic_link(email)
        user = User.first(Sequel.lit("LOWER(email) = ?", email))

        if user
          magic_token = MagicLinkToken.generate_for_user(user)
          frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
          magic_link = magic_token.magic_link_url(frontend_url)

          puts "\n" + ("=" * 60)
          puts "MAGIC LINK FOR #{email}:"
          puts magic_link
          puts ("=" * 60) + "\n"
        else
          puts "No user found for email #{email}"
        end

        Success({ message: "If an account exists with this email, a magic link has been sent." })
      end
    end
  end
end
