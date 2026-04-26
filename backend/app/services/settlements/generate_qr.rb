# frozen_string_literal: true

require "rqrcode"
require "chunky_png"

module Settlements
  # Service to generate an EPC QR code PNG for a settlement transfer.
  # Only the sender (from_user) can request the QR code, since it contains
  # the recipient's IBAN which is otherwise kept private.
  module GenerateQr
    class << self
      include Dry::Monads[:result]

      def call(transfer_id:, membership:)
        LoadPaymentContext.call(transfer_id: transfer_id, membership: membership)
                          .bind { |ctx| generate_png(ctx) }
      end

      private

      def generate_png(ctx)
        transfer = ctx[:transfer]
        event = ctx[:event]
        recipient = ctx[:recipient]

        payload = build_epc_payload(
          recipient_name: (recipient.name || recipient.email.to_s).slice(0, 70),
          iban: recipient.iban,
          amount: transfer.amount,
          description: event.name.slice(0, 140)
        )

        # EPC QR spec limits payload to 331 bytes
        byte_length = payload.bytesize
        if byte_length > 331
          return Failure(ServiceError.validation("Payment description is too long for QR code"))
        end

        qr = RQRCode::QRCode.new(payload, level: :m)
        png = qr.as_png(size: 256, border_modules: 2)

        Success(png.to_blob)
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
