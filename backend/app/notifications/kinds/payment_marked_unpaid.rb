# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to the counterparty when someone reverses a "marked paid"
    # using the Unmark affordance. Without this, a debtor who unmarked
    # too eagerly (or a creditor who realised the money never landed)
    # would silently flip a balance back without the other side knowing.
    # Mirrors `transfer_paid` so any change to settled-state shows up in
    # the audit trail.
    module PaymentMarkedUnpaid
      class << self
        def key = :payment_marked_unpaid
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
              Mailers::EmailRenderer.heading("Payment status reversed"),
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
            "#{actor_name} unmarked their #{formatted} payment"
          else
            "#{actor_name} reverted your #{formatted} payment"
          end
        end

        def body_line_for(actor_role, actor_name, formatted)
          if actor_role == "debtor"
            "#{actor_name} reversed their #{formatted} payment — the balance is open again."
          else
            "#{actor_name} reverted their confirmation of your #{formatted} payment — the balance is open again."
          end
        end

        def format_amount(amount)
          format("€%.2f", amount)
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, actor_name:, amount:, actor_role:, settle_up_url:)
          message = PaymentMarkedUnpaid.build_email(
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
