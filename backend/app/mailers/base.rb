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
      def configure!
        if APP_ENV == "production"
          APP_LOGGER.info { "[Mailer] SMTP delivery configured (credentials loaded on first send)" }
        else
          Mail.defaults { self.delivery_method :test }
          APP_LOGGER.info { "[Mailer] Configured test delivery method" }
        end
      end

      def deliver(message)
        apply_smtp_settings(message) if APP_ENV == "production"
        masked = mask_recipients(message.to)
        APP_LOGGER.info { "[Mailer] Sending email to #{masked} (subject: #{message.subject})" }
        message.deliver
        APP_LOGGER.info { "[Mailer] Email delivered to #{masked}" }
      end

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

      def from_address
        ENV.fetch("SMTP_FROM_EMAIL", "noreply@tayaway.nl")
      end

      def from_name
        ENV.fetch("SMTP_FROM_NAME", "Tayaway")
      end

      def from_header
        "#{from_name} <#{from_address}>"
      end

      def reply_to_address
        value = ENV["SMTP_REPLY_TO_EMAIL"]
        value && !value.empty? ? value : nil
      end

      def unsubscribe_mailto
        address = ENV["SMTP_UNSUBSCRIBE_EMAIL"]
        return nil if address.nil? || address.empty?

        "<mailto:#{address}?subject=unsubscribe>"
      end

      # `unsubscribable` is true for mail a recipient might reasonably want to
      # opt out of (invitations, notifications) and false for mail they directly
      # asked for (login link, email-change verification). Only the former
      # gets a List-Unsubscribe header.
      def apply_sender_headers(message, unsubscribable: false)
        message.from from_header
        message.reply_to reply_to_address if reply_to_address
        message["List-Unsubscribe"] = unsubscribe_mailto if unsubscribable && unsubscribe_mailto
      end

      private

      # Masks email addresses for logging: "iain@example.com" -> "i***@example.com"
      def mask_recipients(addresses)
        return "" if addresses.nil? || addresses.empty?

        addresses.map do |addr|
          local, domain = addr.split("@", 2)
          next addr unless domain

          "#{local[0]}***@#{domain}"
        end.join(", ")
      end

      # Applies SMTP settings directly to the message, reading credentials at
      # send time rather than at boot. This means missing SMTP vars only raise
      # when email is actually sent, not when the app starts.
      def apply_smtp_settings(message)
        smtp_host = ENV.fetch("SMTP_HOST")
        smtp_port = ENV.fetch("SMTP_PORT", "587").to_i
        smtp_username = ENV.fetch("SMTP_USERNAME")
        smtp_password = ENV.fetch("SMTP_PASSWORD")
        smtp_domain = ENV.fetch("SMTP_DOMAIN", "tayaway.nl")

        # Port 465 uses implicit SSL; port 587 uses STARTTLS
        tls_options = if smtp_port == 465
                        { ssl: true, enable_starttls_auto: false }
                      else
                        { ssl: false, enable_starttls_auto: true }
                      end

        message.delivery_method(:smtp, {
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
