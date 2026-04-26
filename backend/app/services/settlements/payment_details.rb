# frozen_string_literal: true

require "base64"
require "rqrcode"
require "chunky_png"

module Settlements
  # Returns everything a sender needs to pay a transfer. The endpoint always
  # succeeds (given a valid sender on a non-paid, non-superseded transfer);
  # individual fields are nil when the data isn't available — most commonly
  # when the recipient hasn't configured an IBAN. The QR PNG is base64 so it
  # rides along in the same JSON response and the client doesn't need a
  # second round-trip.
  module PaymentDetails
    # EPC QR spec caps the encoded payload at 331 bytes. Long event names can
    # push past it; in that case we still return the IBAN so the user can pay
    # manually.
    EPC_PAYLOAD_LIMIT_BYTES = 331

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

        base = {
          recipientName: recipient.name || recipient.email.to_s,
          amount: transfer.amount,
          reference: event.name,
          iban: nil,
          qrPng: nil
        }

        return base unless recipient.iban

        base[:iban] = format_iban(recipient.iban)
        png = build_qr_png(recipient: recipient, event: event, transfer: transfer)
        base[:qrPng] = Base64.strict_encode64(png) if png

        base
      end

      def format_iban(iban)
        iban.gsub(/\s/, "").upcase.scan(/.{1,4}/).join(" ")
      end

      def build_qr_png(recipient:, event:, transfer:)
        payload = build_epc_payload(
          recipient_name: (recipient.name || recipient.email.to_s).slice(0, 70),
          iban: recipient.iban,
          amount: transfer.amount,
          description: event.name.slice(0, 140)
        )

        return nil if payload.bytesize > EPC_PAYLOAD_LIMIT_BYTES

        qr = RQRCode::QRCode.new(payload, level: :m)
        qr.as_png(size: 256, border_modules: 2).to_blob
      end

      def build_epc_payload(recipient_name:, iban:, amount:, description:)
        normalized_iban = iban.gsub(/\s/, "").upcase
        amount_str = "EUR#{format("%.2f", amount)}"

        [
          "BCD",         # Service tag
          "002",         # Version
          "1",           # Character set (UTF-8)
          "SCT",         # Identification code
          "",            # BIC (optional)
          recipient_name,
          normalized_iban,
          amount_str,
          "",            # Purpose code (optional)
          "",            # Structured remittance (optional)
          description,   # Unstructured remittance
          ""             # Beneficiary to originator info (optional)
        ].join("\n")
      end
    end
  end
end
