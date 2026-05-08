# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to a creditor when a settlement is created naming them as the
    # recipient of a transfer. Companion to `settlement_owed` — see that
    # kind for why these are split.
    module SettlementOwesYou
      class << self
        def key = :settlement_owes_you
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(amount:, debtor_name:, event_name:, event_url:, **)
          {
            title: "#{debtor_name} owes you #{format_amount(amount)}",
            body: "for #{event_name}",
            href: event_url
          }
        end

        def build_email(email:, recipient_name:, debtor_name:, amount:, event_name:, event_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"
          formatted = format_amount(amount)

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: "#{debtor_name} owes you #{formatted} for #{event_name}",
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              The expenses for #{event_name} have been settled. #{debtor_name} owes you #{formatted}.

              See the event: #{event_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading("Money coming your way"),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "The expenses for <strong>#{Mailers::EmailRenderer.escape(event_name)}</strong> have been settled.",
                style: :tight,
                raw: true
              ),
              Mailers::EmailRenderer.paragraph(
                "#{Mailers::EmailRenderer.escape(debtor_name)} owes you #{formatted}.",
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
        def call(email:, recipient_name:, debtor_name:, amount:, event_name:, event_url:)
          message = SettlementOwesYou.build_email(
            email: email,
            recipient_name: recipient_name,
            debtor_name: debtor_name,
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
