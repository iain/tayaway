# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to the counterparty when someone marks a netted transfer as
    # paid. The action can be initiated from either side — the debtor
    # asserting "I paid" or the creditor asserting "I received it" — and
    # the message direction follows: debtor-led notifies the creditor
    # that money arrived, creditor-led notifies the debtor that the
    # other party signed off.
    module TransferPaid
      class << self
        def key = :transfer_paid
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(actor_name:, amount:, actor_role:, settle_up_url:, **)
          {
            title: title_for(actor_role, actor_name, amount),
            body: "Tap to review your balances.",
            href: settle_up_url
          }
        end

        def build_email(email:, recipient_name:, actor_name:, amount:, actor_role:, settle_up_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"
          formatted = format_amount(amount)
          subject = title_for(actor_role, actor_name, amount)
          heading = actor_role == "debtor" ? "Payment received" : "Payment confirmed"
          body_line = body_line_for(actor_role, actor_name, formatted)

          Mailers::EmailRenderer.build_message(
            to: email,
            subject: subject,
            unsubscribable: true,
            text_body: <<~TEXT,
              #{greeting}

              #{body_line}

              See your balances: #{settle_up_url}
            TEXT
            html_body: [
              Mailers::EmailRenderer.heading(heading),
              Mailers::EmailRenderer.paragraph(greeting, style: :tight),
              Mailers::EmailRenderer.paragraph(body_line, style: :highlight),
              Mailers::EmailRenderer.button(text: "View balances", href: settle_up_url)
            ].join
          )
        end

        private

        def title_for(actor_role, actor_name, amount)
          formatted = format_amount(amount)
          if actor_role == "debtor"
            "#{actor_name} paid you #{formatted}"
          else
            "#{actor_name} confirmed your #{formatted} payment"
          end
        end

        def body_line_for(actor_role, actor_name, formatted)
          if actor_role == "debtor"
            "#{actor_name} marked your #{formatted} balance as paid."
          else
            "#{actor_name} confirmed receipt of your #{formatted} payment."
          end
        end

        def format_amount(amount)
          format("€%.2f", amount)
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, actor_name:, amount:, actor_role:, settle_up_url:)
          message = TransferPaid.build_email(
            email: email,
            recipient_name: recipient_name,
            actor_name: actor_name,
            amount: amount,
            actor_role: actor_role,
            settle_up_url: settle_up_url
          )
          Mailers::Base.deliver(message)
        end
      end
    end
  end
end
