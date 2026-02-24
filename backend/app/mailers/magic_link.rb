# typed: true
# frozen_string_literal: true

module Mailers
  # Builds and sends the magic link sign-in email.
  #
  # @example
  #   Mailers::MagicLink.send_email(email: "user@example.com", magic_link: "https://...")
  module MagicLink
    class << self
      extend T::Sig

      sig { params(email: T.any(String, EmailAddress), magic_link: String).void }
      def send_email(email:, magic_link:)
        message = build_message(email: email.to_s, magic_link: magic_link)
        Mailers::Base.deliver_later(message)
      end

      private

      sig { params(email: String, magic_link: String).returns(Mail::Message) }
      def build_message(email:, magic_link:)
        message = Mail.new
        message.to      email
        message.from    Mailers::Base.from_address
        message.subject "Sign in to Tayaway"

        text = Mail::Part.new
        text.body = <<~TEXT
          Sign in to Tayaway

          Click the link below to sign in:

          #{magic_link}

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
                    <h1 style="margin:0 0 16px;font-size:24px;color:#18181b;">Sign in to Tayaway</h1>
                    <p style="margin:0 0 32px;font-size:16px;color:#52525b;line-height:1.5;">
                      Click the button below to sign in to your account.
                    </p>
                    <a href="#{magic_link}" style="display:inline-block;background-color:#2563eb;color:#ffffff;font-size:16px;font-weight:600;text-decoration:none;padding:12px 32px;border-radius:6px;">
                      Sign in
                    </a>
                    <p style="margin:32px 0 0;font-size:13px;color:#a1a1aa;line-height:1.5;">
                      Or copy and paste this link:<br>
                      <a href="#{magic_link}" style="color:#2563eb;word-break:break-all;">#{magic_link}</a>
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
