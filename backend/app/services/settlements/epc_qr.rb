# frozen_string_literal: true

require "base64"
require "rqrcode"
require "chunky_png"

module Settlements
  # Shared EPC QR ("BCD") payload + PNG builder. The EPC spec caps the encoded
  # payload at 331 bytes; we return nil when the inputs would push past it so
  # callers can still expose a manually-typeable IBAN.
  module EpcQr
    EPC_PAYLOAD_LIMIT_BYTES = 331

    class << self
      def format_iban(iban)
        iban.gsub(/\s/, "").upcase.scan(/.{1,4}/).join(" ")
      end

      def build_png_base64(recipient_name:, iban:, amount:, description:)
        payload = build_payload(
          recipient_name: recipient_name.slice(0, 70),
          iban: iban,
          amount: amount,
          description: description.slice(0, 140)
        )
        return nil if payload.bytesize > EPC_PAYLOAD_LIMIT_BYTES

        qr = RQRCode::QRCode.new(payload, level: :m)
        png = qr.as_png(size: 256, border_modules: 2).to_blob
        Base64.strict_encode64(png)
      end

      private

      def build_payload(recipient_name:, iban:, amount:, description:)
        [
          "BCD",         # Service tag
          "002",         # Version
          "1",           # Character set (UTF-8)
          "SCT",         # Identification code
          "",            # BIC (optional)
          recipient_name,
          iban.gsub(/\s/, "").upcase,
          "EUR#{format("%.2f", amount)}",
          "",            # Purpose code (optional)
          "",            # Structured remittance (optional)
          description,   # Unstructured remittance
          ""             # Beneficiary to originator info (optional)
        ].join("\n")
      end
    end
  end
end
