# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to fellow workspace members when a new event is created. Mail
    # is off by default — for active workspaces this would be daily noise
    # — but the in-app channel keeps the bell informative without being
    # disruptive.
    module EventCreated
      class << self
        def key = :event_created
        def default_channels = %i[in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(actor_name:, event_name:, workspace_name:, event_url:, **)
          {
            title: "#{event_name}",
            body: "#{actor_name} added a new event to #{workspace_name}",
            href: event_url
          }
        end

        def build_email(email:, recipient_name:, actor_name:, event_name:, workspace_name:, event_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "#{actor_name} added #{event_name} to #{workspace_name}",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              #{actor_name} added a new event to #{workspace_name}: #{event_name}.

              View event: #{event_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("New event"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "#{Mailers::EmailRenderer.escape(actor_name)} added a new event to <strong>#{Mailers::EmailRenderer.escape(workspace_name)}</strong>:",
                style: :tight,
                raw: true
              ),
              Mailers::EmailRenderer.paragraph(event_name, style: :highlight),
              Mailers::EmailRenderer.button(text: "View event", href: event_url)
            ].join
          )
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, actor_name:, event_name:, workspace_name:, event_url:)
          message = EventCreated.build_email(
            email: email,
            recipient_name: recipient_name,
            actor_name: actor_name,
            event_name: event_name,
            workspace_name: workspace_name,
            event_url: event_url
          )
          Mailers::Base.deliver(message)
        end
      end
    end
  end
end
