# frozen_string_literal: true

module Mailers
  # Builds and sends the email change verification email.
  module EmailChange
    class << self
      def send_email(email:, verification_link:)
        Jobs::DeliverEmailChange.perform_later(
          email: email.to_s,
          verification_link: verification_link
        )
      end

      def deliver_now(email:, verification_link:)
        message = build_message(email: email.to_s, verification_link: verification_link)
        Mailers::Base.deliver(message)
      end

      private

      def build_message(email:, verification_link:)
        message = Mail.new
        message.to      email
        message.subject "Confirm your new email address"
        Mailers::Base.apply_sender_headers(message)

        text = Mail::Part.new
        text.body = <<~TEXT
          Confirm your new email address

          You requested to change your Tayaway email to this address. Click the link below to confirm:

          #{verification_link}

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
                    <h1 style="margin:0 0 16px;font-size:24px;color:#18181b;">Confirm your new email</h1>
                    <p style="margin:0 0 32px;font-size:16px;color:#52525b;line-height:1.5;">
                      You requested to change your Tayaway email to this address. Click the button below to confirm.
                    </p>
                    <a href="#{verification_link}" style="display:inline-block;background-color:#2563eb;color:#ffffff;font-size:16px;font-weight:600;text-decoration:none;padding:12px 32px;border-radius:6px;">
                      Confirm email change
                    </a>
                    <p style="margin:32px 0 0;font-size:13px;color:#a1a1aa;line-height:1.5;">
                      Or copy and paste this link:<br>
                      <a href="#{verification_link}" style="color:#2563eb;word-break:break-all;">#{verification_link}</a>
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
  end
end
