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
          APP_LOGGER.info { "[Mailer] SMTP delivery configured (credentials loaded on first send)" }
        else
          Mail.defaults { T.unsafe(self).delivery_method :test }
          APP_LOGGER.info { "[Mailer] Configured test delivery method" }
        end
      end

      sig { params(message: Mail::Message).void }
      def deliver(message)
        apply_smtp_settings(message) if APP_ENV == "production"
        masked = mask_recipients(message.to)
        APP_LOGGER.info { "[Mailer] Sending email to #{masked} (subject: #{message.subject})" }
        message.deliver
        APP_LOGGER.info { "[Mailer] Email delivered to #{masked}" }
      end

      sig { params(message: Mail::Message).void }
      def deliver_later(message)
        if APP_ENV == "production"
          Thread.new do
            deliver(message)
          rescue StandardError => e
            APP_LOGGER.error { "[Mailer] Failed to deliver email to #{mask_recipients(message.to)}: #{e.class} - #{e.message}" }
          end
        else
          deliver(message)
        end
      end

      sig { returns(String) }
      def from_address
        ENV.fetch("SMTP_FROM_EMAIL", "noreply@tayaway.com")
      end

      private

      # Masks email addresses for logging: "iain@example.com" -> "i***@example.com"
      sig { params(addresses: T.nilable(T::Array[String])).returns(String) }
      def mask_recipients(addresses)
        return "" if addresses.nil? || addresses.empty?

        addresses.map do |addr|
          local, domain = addr.split("@", 2)
          next addr unless domain

          "#{T.must(local)[0]}***@#{domain}"
        end.join(", ")
      end

      # Applies SMTP settings directly to the message, reading credentials at
      # send time rather than at boot. This means missing SMTP vars only raise
      # when email is actually sent, not when the app starts.
      sig { params(message: Mail::Message).void }
      def apply_smtp_settings(message)
        smtp_host = ENV.fetch("SMTP_HOST")
        smtp_port = ENV.fetch("SMTP_PORT", "587").to_i
        smtp_username = ENV.fetch("SMTP_USERNAME")
        smtp_password = ENV.fetch("SMTP_PASSWORD")
        smtp_domain = ENV.fetch("SMTP_DOMAIN", "tayaway.com")

        # Port 465 uses implicit SSL; port 587 uses STARTTLS
        tls_options = if smtp_port == 465
                        { ssl: true, enable_starttls_auto: false }
                      else
                        { ssl: false, enable_starttls_auto: true }
                      end

        T.unsafe(message).delivery_method(:smtp, {
          address: smtp_host,
          port: smtp_port,
          user_name: smtp_username,
          password: smtp_password,
          domain: smtp_domain,
          authentication: "plain"
        }.merge(tls_options)
        )
      end
    end
  end
end
