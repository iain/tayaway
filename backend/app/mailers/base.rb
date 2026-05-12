# frozen_string_literal: true

require "mail"

module Mailers
  # Shared mail configuration and delivery helper.
  # Uses :smtp in production, :test everywhere else. Out-of-band sending
  # is the responsibility of the Jobs::Deliver* job classes — each
  # mailer's `send_email` enqueues one of those, and the worker fiber
  # invokes that mailer's `perform_delivery` to build and send the message.
  # Request-path callers must use `send_email`; `perform_delivery` is the
  # synchronous SMTP entry point and only the matching job should call it.
  module Base
    class << self
      def configure!
        if APP_CONFIG.production?
          APP_LOGGER.info { "[Mailer] SMTP delivery configured (credentials loaded on first send)" }
        else
          Mail.defaults { self.delivery_method :test }
          APP_LOGGER.info { "[Mailer] Configured test delivery method" }
        end
      end

      def deliver(message)
        apply_smtp_settings(message) if APP_CONFIG.production?
        masked = mask_recipients(message.to)
        APP_LOGGER.info { "[Mailer] Sending email to #{masked} (subject: #{message.subject})" }
        message.deliver
        APP_LOGGER.info { "[Mailer] Email delivered to #{masked}" }
      end

      def from_address = APP_CONFIG.smtp_from_email
      def from_name    = APP_CONFIG.smtp_from_name
      def from_header  = "#{from_name} <#{from_address}>"

      def reply_to_address
        value = APP_CONFIG.smtp_reply_to_email
        value && !value.empty? ? value : nil
      end

      def unsubscribe_mailto
        address = APP_CONFIG.smtp_unsubscribe_email
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

      def apply_smtp_settings(message)
        # Port 465 uses implicit SSL; port 587 uses STARTTLS
        tls_options = if APP_CONFIG.smtp_port == 465
                        { ssl: true, enable_starttls_auto: false }
                      else
                        { ssl: false, enable_starttls_auto: true }
                      end

        message.delivery_method(:smtp, {
          address: APP_CONFIG.smtp_host,
          port: APP_CONFIG.smtp_port,
          user_name: APP_CONFIG.smtp_username,
          password: APP_CONFIG.smtp_password,
          domain: APP_CONFIG.smtp_domain,
          authentication: "plain"
        }.merge(tls_options)
        )
      end
    end
  end
end
