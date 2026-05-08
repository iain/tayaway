# frozen_string_literal: true

module Mailers
  # Builds and sends the login link sign-in email.
  #
  # @example
  #   Mailers::LoginLink.send_email(email: "user@example.com", login_link: "https://...")
  module LoginLink
    class << self
      def send_email(email:, login_link:, workspace_name: "Tayaway")
        DeliveryJob.perform_later(
          email: email.to_s,
          login_link: login_link,
          workspace_name: workspace_name
        )
      end

      # Synchronous delivery. Only `Mailers::LoginLink::DeliveryJob#call`
      # should invoke this — request-path callers must go through
      # `send_email` so the SMTP round-trip happens on the jobs reactor,
      # not the request fiber.
      def perform_delivery(email:, login_link:, workspace_name: "Tayaway")
        message = build_message(email: email.to_s, login_link: login_link, workspace_name: workspace_name)
        Mailers::Base.deliver(message)
      end

      private

      def build_message(email:, login_link:, workspace_name:)
        EmailRenderer.build_message(
          to: email,
          subject: "Log in to #{workspace_name}",
          text_body: <<~TEXT,
            Log in to #{workspace_name}

            Click the link below to log in:

            #{login_link}

            This link expires in 15 minutes. If you didn't request this, you can safely ignore this email.
          TEXT
          html_body: [
            EmailRenderer.heading("Log in to #{workspace_name}"),
            EmailRenderer.paragraph("Click the button below to log in to your account."),
            EmailRenderer.button(text: "Log in", href: login_link),
            EmailRenderer.muted_link(prefix: "Or copy and paste this link:", href: login_link),
            EmailRenderer.footer("This link expires in 15 minutes. If you didn’t request this, you can safely ignore this email.")
          ].join
        )
      end
    end

    class DeliveryJob < Jobs::Base
      def call(email:, login_link:, workspace_name: "Tayaway")
        Mailers::LoginLink.perform_delivery(
          email: email,
          login_link: login_link,
          workspace_name: workspace_name
        )
      end
    end
  end
end
