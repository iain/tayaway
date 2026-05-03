# frozen_string_literal: true

module Settlements
  # Returns everything a sender needs to pay a transfer. The endpoint always
  # succeeds (given a valid sender on a non-paid, non-superseded transfer);
  # individual fields are nil when the data isn't available — most commonly
  # when the recipient hasn't configured an IBAN. The QR PNG is base64 so it
  # rides along in the same JSON response and the client doesn't need a
  # second round-trip.
  module PaymentDetails
    class << self
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

        base = {
          recipientName: recipient.name || recipient.email.to_s,
          amount: transfer.amount,
          reference: event.name,
          iban: nil,
          qrPng: nil
        }

        return base unless recipient.iban

        base[:iban] = EpcQr.format_iban(recipient.iban)
        base[:qrPng] = EpcQr.build_png_base64(
          recipient_name: recipient.iban_holder_name || recipient.name || recipient.email.to_s,
          iban: recipient.iban,
          amount: transfer.amount,
          description: event.name
        )

        base
      end
    end
  end
end
