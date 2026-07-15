# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to going members when an event is deleted. Email is
    # on by default here (unlike `event_created`) because cancellation is
    # higher-stakes — a date that quietly disappeared from the pool while
    # someone wasn't looking is exactly the kind of thing an inbox alert
    # is meant to catch. The href points at the workspace home rather
    # than the (now-gone) event page.
    module EventCanceled
      class << self
        def key = :event_canceled
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(event_name:, actor_name:, workspace_url:, **)
          {
            title: "#{event_name} was canceled",
            body: "#{actor_name} deleted the event.",
            href: workspace_url
          }
        end

        def build_email(email:, recipient_name:, actor_name:, event_name:, workspace_name:, workspace_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "#{event_name} was canceled",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              #{actor_name} canceled #{event_name} in #{workspace_name}.

              View workspace: #{workspace_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("Event canceled"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "#{Mailers::EmailRenderer.escape(actor_name)} canceled <strong>#{Mailers::EmailRenderer.escape(event_name)}</strong> in #{Mailers::EmailRenderer.escape(workspace_name)}.",
                style: :highlight,
                raw: true
              ),
              Mailers::EmailRenderer.button(text: "View workspace", href: workspace_url)
            ].join
          )
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, actor_name:, event_name:, workspace_name:, workspace_url:)
          message = EventCanceled.build_email(
            email: email,
            recipient_name: recipient_name,
            actor_name: actor_name,
            event_name: event_name,
            workspace_name: workspace_name,
            workspace_url: workspace_url
          )
          Mailers::Base.deliver(message)
        end
      end
    end
  end
end
