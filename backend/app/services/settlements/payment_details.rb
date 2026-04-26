# frozen_string_literal: true

module Settlements
  # Returns the data a sender needs to pay a transfer manually from a mobile
  # banking app: the recipient's IBAN (formatted in groups of four for easy
  # reading), their name, the amount, and the reference. Authorization
  # mirrors GenerateQr — only the sender of an unpaid, non-superseded
  # transfer may see the IBAN.
  module PaymentDetails
    class << self
      include Dry::Monads[:result]

      def call(transfer_id:, membership:)
        Success()
          .bind { LoadPaymentContext.call(transfer_id: transfer_id, membership: membership) }
          .fmap { |ctx| build(ctx) }
      end

      private

      def build(ctx)
        transfer = ctx[:transfer]
        event = ctx[:event]
        recipient = ctx[:recipient]

        {
          recipientName: recipient.name || recipient.email.to_s,
          iban: format_iban(recipient.iban),
          amount: transfer.amount,
          reference: event.name
        }
      end

      def format_iban(iban)
        iban.gsub(/\s/, "").upcase.scan(/.{1,4}/).join(" ")
      end
    end
  end
end
