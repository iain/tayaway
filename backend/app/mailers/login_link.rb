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

      # Synchronous delivery. Only `Jobs::DeliverLoginLink#call` should
      # invoke this — request-path callers must go through `send_email`
      # so the SMTP round-trip happens on the jobs reactor, not the
      # request fiber.
      def perform_delivery(email:, login_link:, workspace_name: "Tayaway")
        message = build_message(email: email.to_s, login_link: login_link, workspace_name: workspace_name)
        Mailers::Base.deliver(message)
      end

      private

      def build_message(email:, login_link:, workspace_name:)
        message = Mail.new
        message.to      email
        message.subject "Log in to #{workspace_name}"
        Mailers::Base.apply_sender_headers(message)

        text = Mail::Part.new
        text.body = <<~TEXT
          Log in to #{workspace_name}

          Click the link below to log in:

          #{login_link}

          This link expires in 15 minutes. If you didn't request this, you can safely ignore this email.
        TEXT
        message.text_part = text

        html = Mail::Part.new
        html.content_type = "text/html; charset=UTF-8"
        html.body = <<~HTML
          <!DOCTYPE html>
          <html>
          <head><meta charset="UTF-8"></head>
          <body style="margin:0;padding:0;background-color:#f4f4f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
            <table width="100%" cellpadding="0" cellspacing="0" style="background-color:#f4f4f5;padding:40px 0;">
              <tr><td align="center">
                <table width="480" cellpadding="0" cellspacing="0" style="background-color:#ffffff;border-radius:8px;padding:40px;">
                  <tr><td style="text-align:center;">
                    <h1 style="margin:0 0 16px;font-size:24px;color:#18181b;">Log in to #{workspace_name}</h1>
                    <p style="margin:0 0 32px;font-size:16px;color:#52525b;line-height:1.5;">
                      Click the button below to log in to your account.
                    </p>
                    <a href="#{login_link}" style="display:inline-block;background-color:#2563eb;color:#ffffff;font-size:16px;font-weight:600;text-decoration:none;padding:12px 32px;border-radius:6px;">
                      Log in
                    </a>
                    <p style="margin:32px 0 0;font-size:13px;color:#a1a1aa;line-height:1.5;">
                      Or copy and paste this link:<br>
                      <a href="#{login_link}" style="color:#2563eb;word-break:break-all;">#{login_link}</a>
                    </p>
                    <p style="margin:24px 0 0;font-size:13px;color:#a1a1aa;">
                      This link expires in 15 minutes. If you didn&rsquo;t request this, you can safely ignore this email.
                    </p>
                  </td></tr>
                </table>
              </td></tr>
            </table>
          </body>
          </html>
        HTML
        message.html_part = html

        message
      end
    end

    # Inner job class that drives the out-of-band delivery — `send_email`
    # enqueues one of these and the worker calls back into
    # `Mailers::LoginLink.perform_delivery`. Lives here so the mailer is
    # self-contained: the build/deliver code and the queue glue ship in
    # one file.
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
