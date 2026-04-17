# frozen_string_literal: true

require "rbnacl"
require "openssl"
require "base64"

# libsodium (XSalsa20-Poly1305) encryption helper for sensitive fields.
#
# Stored format (v1): Base64(0x01 ‖ nonce ‖ mac ‖ ciphertext)
# Legacy unversioned:  Base64(nonce ‖ mac ‖ ciphertext)
#
# Reads accept both; writes always emit v1.
module Encryption
  VERSION_1 = "\x01".b.freeze

  # Nonce (24) + MAC (16) — minimum ciphertext payload for any plaintext.
  NONCE_BYTES = RbNaCl::SecretBox.nonce_bytes # 24
  MAC_BYTES   = 16 # Poly1305
  MIN_ENCRYPTED_BYTES = NONCE_BYTES + MAC_BYTES # 40

  class << self
    def encrypt(plaintext)
      raw = box.box(plaintext)
      Base64.strict_encode64(VERSION_1 + raw)
    end

    def decrypt(encoded)
      raw = Base64.strict_decode64(encoded)

      if raw.start_with?(VERSION_1)
        box.open(raw.byteslice(1..))
      else
        box.open(raw)
      end
    end

    def encrypted?(value)
      raw = Base64.strict_decode64(value)

      if raw.start_with?(VERSION_1)
        raw.bytesize >= 1 + MIN_ENCRYPTED_BYTES
      else
        raw.bytesize >= MIN_ENCRYPTED_BYTES
      end
    rescue ArgumentError
      false
    end

    private

    def box
      @_box ||= RbNaCl::SimpleBox.from_secret_key(encryption_key)
    end

    def encryption_key
      # Derive a 32-byte key from APP_SECRET using HKDF
      OpenSSL::KDF.hkdf(
        APP_SECRET,
        salt: "tayaway-iban-encryption",
        info: "iban-nacl-secretbox",
        length: 32,
        hash: "SHA256"
      )
    end
  end
end
