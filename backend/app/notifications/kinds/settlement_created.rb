# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to both sides of every transfer in a freshly-created settlement.
    # The two recipients see different copy — debtor reads "you owe X",
    # creditor reads "X owes you" — but it's a single user-facing kind
    # ("a settlement happened to you") because the underlying event is the
    # same. Splitting it into two registry entries would just produce a
    # preferences UI where opting into one direction without the other
    # doesn't really make sense (the system always fires both halves).
    module SettlementCreated
      class << self
        def key = :settlement_created
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(amount:, counterparty_name:, recipient_role:, event_name:, event_url:, **)
          {
            title: title_for(recipient_role, counterparty_name, amount),
            body: "for #{event_name}",
            href: event_url
          }
        end

        def build_email(email:, recipient_name:, counterparty_name:, recipient_role:, amount:, event_name:, event_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"
          formatted = format_amount(amount)
          subject = "#{title_for(recipient_role, counterparty_name, amount)} for #{event_name}"
          heading = recipient_role == "debtor" ? "Time to settle up" : "Money coming your way"
          balance_line = balance_line(recipient_role, counterparty_name, formatted)

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: subject,
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              The expenses for #{event_name} have been settled. #{balance_line}

              See the event: #{event_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading(heading),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(
                "The expenses for <strong>#{Mailers::EmailRenderer.escape(event_name)}</strong> have been settled.",
                style: :tight,
                raw: true
              ),
              Mailers::EmailRenderer.paragraph(balance_line, style: :highlight),
              Mailers::EmailRenderer.button(text: "View event", href: event_url)
            ].join
          )
        end

        private

        def title_for(recipient_role, counterparty_name, amount)
          formatted = format_amount(amount)
          if recipient_role == "debtor"
            "You owe #{counterparty_name} #{formatted}"
          else
            "#{counterparty_name} owes you #{formatted}"
          end
        end

        def balance_line(recipient_role, counterparty_name, formatted)
          if recipient_role == "debtor"
            "You owe #{counterparty_name} #{formatted}."
          else
            "#{counterparty_name} owes you #{formatted}."
          end
        end

        def format_amount(amount)
          format("€%.2f", amount)
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, counterparty_name:, recipient_role:, amount:, event_name:, event_url:)
          message = SettlementCreated.build_email(
            email: email,
            recipient_name: recipient_name,
            counterparty_name: counterparty_name,
            recipient_role: recipient_role,
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
