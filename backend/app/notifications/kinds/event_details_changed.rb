# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to attending event members when the event's dates or location
    # change after they've RSVPed. Defaults to in-app only — for active
    # event planning, mirroring every detail tweak to email would be
    # noisy.
    module EventDetailsChanged
      class << self
        def key = :event_details_changed
        def default_channels = [:in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(event_name:, change_summary:, event_url:, **)
          {
            title: "#{event_name} updated",
            body: change_summary,
            href: event_url
          }
        end

        def build_email(email:, recipient_name:, event_name:, change_summary:, event_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "#{event_name} updated",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              Details changed for #{event_name}: #{change_summary}.

              See the event: #{event_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("Event updated"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "Details changed for <strong>#{Mailers::EmailRenderer.escape(event_name)}</strong>:",
                style: :tight,
                raw: true
              ),
              Mailers::EmailRenderer.paragraph(change_summary, style: :highlight),
              Mailers::EmailRenderer.button(text: "View event", href: event_url)
            ].join
          )
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, event_name:, change_summary:, event_url:)
          message = EventDetailsChanged.build_email(
            email: email,
            recipient_name: recipient_name,
            event_name: event_name,
            change_summary: change_summary,
            event_url: event_url
          )
          Mailers::Base.deliver(message)
        end
      end
    end
  end
end
