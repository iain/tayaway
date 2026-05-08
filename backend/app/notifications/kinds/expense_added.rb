# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to attending event members when a new expense is logged.
    # Defaults to in-app only — for high-frequency events, mirroring it
    # to email would be noisy. Users can opt into the email channel.
    module ExpenseAdded
      class << self
        def key = :expense_added
        def default_channels = [:in_app]
        def supported_channels = %i[email in_app]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(actor_name:, description:, amount:, event_name:, event_url:, **)
          {
            title: "New expense in #{event_name}",
            body: "#{actor_name} added #{description} (#{format_amount(amount)})",
            href: event_url
          }
        end

        def build_email(email:, recipient_name:, actor_name:, description:, amount:, event_name:, event_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"
          formatted = format_amount(amount)

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "New expense in #{event_name}",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              #{actor_name} added an expense to #{event_name}: #{description} (#{formatted}).

              See the event: #{event_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("New expense"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "#{Mailers::EmailRenderer.escape(actor_name)} added an expense to <strong>#{Mailers::EmailRenderer.escape(event_name)}</strong>:",
                style: :tight,
                raw: true
              ),
              Mailers::EmailRenderer.paragraph(
                "#{Mailers::EmailRenderer.escape(description)} — #{formatted}",
                style: :highlight
              ),
              Mailers::EmailRenderer.button(text: "View event", href: event_url)
            ].join
          )
        end

        private

        def format_amount(amount)
          format("€%.2f", amount)
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, actor_name:, description:, amount:, event_name:, event_url:)
          message = ExpenseAdded.build_email(
            email: email,
            recipient_name: recipient_name,
            actor_name: actor_name,
            description: description,
            amount: amount,
            event_name: event_name,
            event_url: event_url
          )
          Mailers::Base.deliver(message)
        end
      end
    end
  end
end
