# typed: true
# frozen_string_literal: true

require "mail"

module Mailers
  # Shared mail configuration and delivery helper.
  # Uses :smtp in production, :test everywhere else.
  #
  # @example
  #   Mailers::Base.configure!
  #   Mailers::Base.deliver(message)
  module Base
    class << self
      extend T::Sig

      sig { void }
      def configure!
        if APP_ENV == "production"
          configure_smtp
        else
          Mail.defaults { T.unsafe(self).delivery_method :test }
        end
        APP_LOGGER.info { "[Mailer] Configured delivery method: #{APP_ENV == "production" ? "smtp" : "test"}" }
      end

      sig { params(message: Mail::Message).void }
      def deliver(message)
        message.deliver
        APP_LOGGER.info { "[Mailer] Email queued to #{message.to&.join(", ")}" }
      rescue StandardError => e
        APP_LOGGER.error { "[Mailer] Failed to deliver email: #{e.message}" }
      end

      sig { returns(String) }
      def from_address
        ENV.fetch("SMTP_FROM_EMAIL", "noreply@tayaway.com")
      end

      private

      sig { void }
      def configure_smtp
        smtp_host = ENV.fetch("SMTP_HOST")
        smtp_port = ENV.fetch("SMTP_PORT", "587").to_i
        smtp_username = ENV.fetch("SMTP_USERNAME")
        smtp_password = ENV.fetch("SMTP_PASSWORD")
        smtp_domain = ENV.fetch("SMTP_DOMAIN", "tayaway.com")

        Mail.defaults do
          T.unsafe(self).delivery_method :smtp,
                                         address: smtp_host,
                                         port: smtp_port,
                                         user_name: smtp_username,
                                         password: smtp_password,
                                         domain: smtp_domain,
                                         authentication: "plain",
                                         enable_starttls_auto: true
        end
      end
    end
  end
end
