# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to a debtor when a settlement is created assigning them a
    # transfer to pay. Separate from `settlement_owes_you` so users can
    # turn just one direction on or off — some people want to know when
    # money is coming in but find "you owe" reminders nagging, or
    # vice versa.
    module SettlementOwed
      class << self
        def key = :settlement_owed
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(amount:, creditor_name:, event_name:, event_url:, **)
          {
            title: "You owe #{creditor_name} #{format_amount(amount)}",
            body: "for #{event_name}",
            href: event_url
          }
        end

        def build_email(email:, recipient_name:, creditor_name:, amount:, event_name:, event_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"
          formatted = format_amount(amount)

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "You owe #{creditor_name} #{formatted} for #{event_name}",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              The expenses for #{event_name} have been settled. You owe #{creditor_name} #{formatted}.

              See the event for payment details: #{event_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("Time to settle up"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "The expenses for <strong>#{Mailers::EmailRenderer.escape(event_name)}</strong> have been settled.",
                style: :tight,
                raw: true
              ),
              Mailers::EmailRenderer.paragraph(
                "You owe #{Mailers::EmailRenderer.escape(creditor_name)} #{formatted}.",
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
        def call(email:, recipient_name:, creditor_name:, amount:, event_name:, event_url:)
          message = SettlementOwed.build_email(
            email: email,
            recipient_name: recipient_name,
            creditor_name: creditor_name,
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
