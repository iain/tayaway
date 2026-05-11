# frozen_string_literal: true

module Mailers
  # Builds and sends the email change verification email.
  module EmailChange
    class << self
      def send_email(email:, verification_link:)
        DeliveryJob.perform_later(
          email: email.to_s,
          verification_link: verification_link
        )
      end

      # Synchronous delivery. Only `Mailers::EmailChange::DeliveryJob#call`
      # should invoke this — request-path callers must go through `send_email`.
      def perform_delivery(email:, verification_link:)
        message = build_message(email: email.to_s, verification_link: verification_link)
        Mailers::Base.deliver(message)
      end

      private

      def build_message(email:, verification_link:)
        EmailRenderer.build_message(
          to: email,
          subject: "Confirm your new email address",
          text_body: <<~TEXT,
            Confirm your new email address

            You requested to change your Tayaway email to this address. Click the link below to confirm:

            #{verification_link}

            This link expires in 15 minutes. If you didn't request this, you can safely ignore this email.
          TEXT
          html_body: [
            EmailRenderer.heading("Confirm your new email"),
            EmailRenderer.paragraph("You requested to change your Tayaway email to this address. Click the button below to confirm."),
            EmailRenderer.button(text: "Confirm email change", href: verification_link),
            EmailRenderer.muted_link(prefix: "Or copy and paste this link:", href: verification_link),
            EmailRenderer.footer("This link expires in 15 minutes. If you didn’t request this, you can safely ignore this email.")
          ].join
        )
      end
    end

    class DeliveryJob < Jobs::Base
      def call(email:, verification_link:)
        Mailers::EmailChange.perform_delivery(email: email, verification_link: verification_link)
      end
    end
  end
end
