# typed: true
# frozen_string_literal: true

require "rbnacl"
require "openssl"
require "base64"

# libsodium (XSalsa20-Poly1305) encryption helper for sensitive fields (e.g. IBANs).
# RbNaCl::SimpleBox handles nonce generation automatically. The ciphertext is stored
# as Base64-encoded "nonce + mac + ciphertext" so it can live in a TEXT column.
module Encryption
  # Nonce (24) + MAC (16) — minimum output length for any plaintext.
  NONCE_BYTES = RbNaCl::SecretBox.nonce_bytes # 24
  MAC_BYTES   = 16 # Poly1305
  MIN_ENCRYPTED_BYTES = NONCE_BYTES + MAC_BYTES # 40

  class << self
    extend T::Sig

    sig { params(plaintext: String).returns(String) }
    def encrypt(plaintext)
      Base64.strict_encode64(box.box(plaintext))
    end

    sig { params(encoded: String).returns(String) }
    def decrypt(encoded)
      box.open(Base64.strict_decode64(encoded))
    end

    # Detect whether a value is encrypted (Base64-encoded with enough bytes for nonce + mac).
    sig { params(value: String).returns(T::Boolean) }
    def encrypted?(value)
      # Plaintext IBANs are alphanumeric (A-Z0-9), never contain + / =
      return false if value.match?(/\A[A-Z]{2}\d{2}[A-Z0-9]{4,30}\z/)

      raw = Base64.strict_decode64(value)
      raw.bytesize >= MIN_ENCRYPTED_BYTES
    rescue ArgumentError
      false
    end

    private

    sig { returns(RbNaCl::SimpleBox) }
    def box
      @box = T.let(@box, T.nilable(RbNaCl::SimpleBox))
      @_box ||= RbNaCl::SimpleBox.from_secret_key(encryption_key)
    end

    sig { returns(String) }
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
