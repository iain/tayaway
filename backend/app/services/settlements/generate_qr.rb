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
        SettlementTransfer.find_result(transfer_id)
                          .bind { |transfer| SettlementTransferPolicy.enforce(:generate_qr, transfer, membership: membership) }
                          .bind { |transfer| load_context(transfer) }
                          .bind { |ctx| generate_png(ctx) }
      end

      private

      def load_context(transfer)
        settlement = Settlement.find(transfer.settlement_id)
        unless settlement
          return Failure(ServiceError.not_found("Settlement not found"))
        end

        event = Event.find(settlement.event_id)
        unless event
          return Failure(ServiceError.not_found("Event not found"))
        end

        recipient = User.find(transfer.to_user_id)
        unless recipient
          return Failure(ServiceError.not_found("Recipient not found"))
        end

        unless recipient.iban
          return Failure(ServiceError.validation("Recipient has no IBAN configured"))
        end

        Success(
          {
            transfer: transfer,
            event: event,
            recipient: recipient
          }
        )
      end

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
