# typed: true
# frozen_string_literal: true

require "rqrcode"
require "chunky_png"

module Settlements
  # Service to generate an EPC QR code PNG for a settlement transfer.
  # Only the sender (from_user) can request the QR code, since it contains
  # the recipient's IBAN which is otherwise kept private.
  module GenerateQr
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          transfer_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID)
        ).returns(Result[String, ServiceError])
      end
      def call(transfer_id:, current_user_id:)
        SettlementTransfer.find_result(transfer_id)
                          .bind { |transfer| authorize(transfer, current_user_id) }
                          .bind { |transfer| load_context(transfer, current_user_id) }
                          .bind { |ctx| generate_png(ctx) }
      end

      private

      sig { params(transfer: SettlementTransfer, current_user_id: T.any(String, UUID)).returns(Result[SettlementTransfer, ServiceError]) }
      def authorize(transfer, current_user_id)
        if transfer.from_user_id&.to_s == current_user_id.to_s
          T.cast(Success(transfer), Result[SettlementTransfer, ServiceError])
        else
          T.cast(Failure(ServiceError.forbidden("Only the sender can request the QR code")), Result[SettlementTransfer, ServiceError])
        end
      end

      sig { params(transfer: SettlementTransfer, current_user_id: T.any(String, UUID)).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def load_context(transfer, current_user_id)
        settlement = Settlement.find(transfer.settlement_id)
        unless settlement
          return T.cast(Failure(ServiceError.not_found("Settlement not found")), Result[T::Hash[Symbol, T.untyped], ServiceError])
        end

        event = Event.find(settlement.event_id)
        unless event
          return T.cast(Failure(ServiceError.not_found("Event not found")), Result[T::Hash[Symbol, T.untyped], ServiceError])
        end

        unless WorkspaceMembership.find_by_workspace_and_user(event.workspace_id, current_user_id)
          return T.cast(Failure(ServiceError.forbidden("Access denied")), Result[T::Hash[Symbol, T.untyped], ServiceError])
        end

        recipient = User.find(T.must(transfer.to_user_id))
        unless recipient
          return T.cast(Failure(ServiceError.not_found("Recipient not found")), Result[T::Hash[Symbol, T.untyped], ServiceError])
        end

        unless recipient.iban
          return T.cast(Failure(ServiceError.validation("Recipient has no IBAN configured")), Result[T::Hash[Symbol, T.untyped], ServiceError])
        end

        T.cast(
          Success(
            {
              transfer: transfer,
              event: event,
              recipient: recipient
            }
          ),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end

      sig { params(ctx: T::Hash[Symbol, T.untyped]).returns(Result[String, ServiceError]) }
      def generate_png(ctx)
        transfer = T.cast(ctx[:transfer], SettlementTransfer)
        event = T.cast(ctx[:event], Event)
        recipient = T.cast(ctx[:recipient], User)

        payload = build_epc_payload(
          recipient_name: T.must((recipient.name || recipient.email.to_s).slice(0, 70)),
          iban: T.must(recipient.iban),
          amount: transfer.amount,
          description: T.must(event.name.slice(0, 140))
        )

        # EPC QR spec limits payload to 331 bytes
        byte_length = payload.bytesize
        if byte_length > 331
          return T.cast(Failure(ServiceError.validation("Payment description is too long for QR code")), Result[String, ServiceError])
        end

        qr = RQRCode::QRCode.new(payload, level: :m)
        png = qr.as_png(size: 256, border_modules: 2)

        T.cast(Success(png.to_blob), Result[String, ServiceError])
      end

      sig { params(recipient_name: String, iban: String, amount: Float, description: String).returns(String) }
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
