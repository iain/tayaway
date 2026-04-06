# frozen_string_literal: true

require "rqrcode"
require "chunky_png"

module Settlements
  # Service to generate an EPC QR code PNG for a settlement transfer.
  # Only the sender (from_user) can request the QR code, since it contains
  # the recipient's IBAN which is otherwise kept private.
  module GenerateQr
    class << self
      include Result::Methods

      def call(transfer_id:, current_user_id:)
        SettlementTransfer.find_result(transfer_id)
                          .bind { |transfer| authorize(transfer, current_user_id) }
                          .bind { |transfer| load_context(transfer, current_user_id) }
                          .bind { |ctx| generate_png(ctx) }
      end

      private

      def authorize(transfer, current_user_id)
        if transfer.from_user_id&.to_s == current_user_id.to_s
          Success(transfer)
        else
          Failure(ServiceError.forbidden("Only the sender can request the QR code"))
        end
      end

      def load_context(transfer, current_user_id)
        settlement = Settlement.find(transfer.settlement_id)
        unless settlement
          return Failure(ServiceError.not_found("Settlement not found"))
        end

        event = Event.find(settlement.event_id)
        unless event
          return Failure(ServiceError.not_found("Event not found"))
        end

        unless WorkspaceMembership.find_by_workspace_and_user(event.workspace_id, current_user_id)
          return Failure(ServiceError.forbidden("Access denied"))
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
