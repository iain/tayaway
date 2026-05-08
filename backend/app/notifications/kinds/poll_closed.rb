# frozen_string_literal: true

module Notifications
  module Kinds
    # Confirmation that a date poll has resolved, with an ICS attachment
    # for the chosen dates. Recipients can opt out of the email channel
    # for users who track plans elsewhere.
    module PollClosed
      class << self
        def key = :poll_closed
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(event_name:, date_label:, event_url:, **)
          {
            title: "Dates confirmed: #{event_name}",
            body: date_label,
            href: event_url
          }
        end

        def build_email(email:, user_name:, event_name:, date_label:, event_url:, ics_content:, ics_filename:, auto_rsvped:)
          greeting = user_name && !user_name.empty? ? "Hi #{user_name}," : "Hi,"
          rsvp_text = if auto_rsvped
                        "You've been RSVPed as attending based on your vote."
                      else
                        "Head to the event page to RSVP and let everyone know if you can make it."
                      end

          message = Mailers::EmailRenderer.build_message(
            to: email,
            subject: "Dates confirmed for #{event_name}",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              The dates for #{event_name} have been confirmed: #{date_label}

              #{rsvp_text}

              View the event: #{event_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("Dates confirmed"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "The dates for <strong>#{Mailers::EmailRenderer.escape(event_name)}</strong> have been confirmed:",
                style: :tight,
                raw: true
              ),
              Mailers::EmailRenderer.paragraph(date_label, style: :highlight),
              Mailers::EmailRenderer.paragraph(rsvp_text),
              Mailers::EmailRenderer.button(text: "View event", href: event_url)
            ].join
          )

          message.attachments[ics_filename] = {
            mime_type: "text/calendar; charset=UTF-8; method=PUBLISH",
            content: ics_content
          }

          message
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, user_name:, event_name:, date_label:, event_url:, ics_content:, ics_filename:, auto_rsvped:)
          message = PollClosed.build_email(
            email: email,
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
      end
    end
  end
end
