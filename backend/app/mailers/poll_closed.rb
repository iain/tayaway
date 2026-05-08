# frozen_string_literal: true

module Mailers
  # Builds and sends the poll-closed notification email with ICS attachment.
  module PollClosed
    class << self
      def send_email(email:, user_name:, event_name:, date_label:, event_url:, ics_content:, ics_filename:, auto_rsvped:)
        DeliveryJob.perform_later(
          email: email.to_s,
          user_name: user_name,
          event_name: event_name,
          date_label: date_label,
          event_url: event_url,
          ics_content: ics_content,
          ics_filename: ics_filename,
          auto_rsvped: auto_rsvped
        )
      end

      # Synchronous delivery. Only `Jobs::DeliverPollClosed#call` should
      # invoke this — request-path callers must go through `send_email`.
      def perform_delivery(email:, user_name:, event_name:, date_label:, event_url:, ics_content:, ics_filename:, auto_rsvped:)
        message = build_message(
          email: email.to_s,
          user_name: user_name,
          event_name: event_name,
          date_label: date_label,
          event_url: event_url,
          ics_content: ics_content,
          ics_filename: ics_filename,
          auto_rsvped: auto_rsvped
        )
        Mailers::Base.deliver(message)
      end

      private

      def build_message(email:, user_name:, event_name:, date_label:, event_url:, ics_content:, ics_filename:, auto_rsvped:)
        greeting = user_name && !user_name.empty? ? "Hi #{user_name}," : "Hi,"
        rsvp_text = if auto_rsvped
                      "You've been RSVPed as attending based on your vote."
                    else
                      "Head to the event page to RSVP and let everyone know if you can make it."
                    end

        message = Mail.new
        message.to      email
        message.subject "Dates confirmed for #{event_name}"
        Mailers::Base.apply_sender_headers(message, unsubscribable: true)

        message.attachments[ics_filename] = {
          mime_type: "text/calendar; charset=UTF-8; method=PUBLISH",
          content: ics_content
        }

        text = Mail::Part.new
        text.body = <<~TEXT
          #{greeting}

          The dates for #{event_name} have been confirmed: #{date_label}

          #{rsvp_text}

          View the event: #{event_url}
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
                    <h1 style="margin:0 0 16px;font-size:24px;color:#18181b;">Dates confirmed</h1>
                    <p style="margin:0 0 8px;font-size:16px;color:#52525b;line-height:1.5;">
                      #{greeting}
                    </p>
                    <p style="margin:0 0 8px;font-size:16px;color:#52525b;line-height:1.5;">
                      The dates for <strong>#{event_name}</strong> have been confirmed:
                    </p>
                    <p style="margin:0 0 24px;font-size:20px;font-weight:600;color:#18181b;">
                      #{date_label}
                    </p>
                    <p style="margin:0 0 32px;font-size:16px;color:#52525b;line-height:1.5;">
                      #{rsvp_text}
                    </p>
                    <a href="#{event_url}" style="display:inline-block;background-color:#2563eb;color:#ffffff;font-size:16px;font-weight:600;text-decoration:none;padding:12px 32px;border-radius:6px;">
                      View event
                    </a>
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

    # See Mailers::LoginLink::DeliveryJob for the rationale on inlining.
    class DeliveryJob < Jobs::Base
      def call(email:, user_name:, event_name:, date_label:, event_url:, ics_content:, ics_filename:, auto_rsvped:)
        Mailers::PollClosed.perform_delivery(
          email: email,
          user_name: user_name,
          event_name: event_name,
          date_label: date_label,
          event_url: event_url,
          ics_content: ics_content,
          ics_filename: ics_filename,
          auto_rsvped: auto_rsvped
        )
      end
    end
  end
end
