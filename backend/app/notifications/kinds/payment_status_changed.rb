# frozen_string_literal: true

module Notifications
  module Kinds
    # Sent to the counterparty when the paid state of a balance moves —
    # either side asserting "I paid" / "I received it" via mark-paid, or
    # reversing that assertion via mark-unpaid. One kind because "tell me
    # when a payment's status changes" is the user-facing preference;
    # opting into the marks-paid half but not the reversals half doesn't
    # reflect a real choice. Copy branches on (action, actor_role) so the
    # message reflects which side took the action and in which direction.
    module PaymentStatusChanged
      class << self
        def key = :payment_status_changed
        def default_channels = %i[email in_app]
        def supported_channels = %i[email in_app push]
        def email_delivery_job = EmailDeliveryJob

        def in_app_payload(action:, actor_name:, amount:, actor_role:, settle_up_url:, **)
          {
            title: title_for(action, actor_role, actor_name, amount),
            body: "Tap to review your balances.",
            href: settle_up_url
          }
        end

        def build_email(email:, recipient_name:, action:, actor_name:, amount:, actor_role:, settle_up_url:)
          greeting = recipient_name && !recipient_name.empty? ? "Hi #{recipient_name}," : "Hi,"
          formatted = format_amount(amount)
          subject = title_for(action, actor_role, actor_name, amount)
          heading = heading_for(action, actor_role)
          body_line = body_line_for(action, actor_role, actor_name, formatted)

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

        def title_for(action, actor_role, actor_name, amount)
          formatted = format_amount(amount)
          case [action, actor_role]
          when ["paid", "debtor"] then "#{actor_name} paid you #{formatted}"
          when ["paid", "creditor"] then "#{actor_name} confirmed your #{formatted} payment"
          when ["unpaid", "debtor"] then "#{actor_name} unmarked their #{formatted} payment"
          when ["unpaid", "creditor"] then "#{actor_name} reverted your #{formatted} payment"
          else "Payment status updated"
          end
        end

        def heading_for(action, _actor_role)
          action == "paid" ? "Payment received" : "Payment status reversed"
        end

        def body_line_for(action, actor_role, actor_name, formatted)
          case [action, actor_role]
          when ["paid", "debtor"]
            "#{actor_name} marked your #{formatted} balance as paid."
          when ["paid", "creditor"]
            "#{actor_name} confirmed receipt of your #{formatted} payment."
          when ["unpaid", "debtor"]
            "#{actor_name} reversed their #{formatted} payment — the balance is open again."
          when ["unpaid", "creditor"]
            "#{actor_name} reverted their confirmation of your #{formatted} payment — the balance is open again."
          else
            "The status of a #{formatted} balance changed."
          end
        end
        # rubocop:enable Style/CombinableLoops

        def format_amount(amount)
          format("€%.2f", amount)
        end
      end

      class EmailDeliveryJob < Jobs::Base
        def call(email:, recipient_name:, action:, actor_name:, amount:, actor_role:, settle_up_url:)
          message = PaymentStatusChanged.build_email(
            email: email,
            recipient_name: recipient_name,
            action: action,
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
