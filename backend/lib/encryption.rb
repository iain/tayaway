# typed: true
# frozen_string_literal: true

require "openssl"
require "base64"

# AES-256-GCM encryption helper for sensitive fields (e.g. IBANs).
# Each encryption uses a unique random nonce. The ciphertext is stored as
# Base64-encoded "nonce + ciphertext + auth_tag" so it can live in a TEXT column.
module Encryption
  ALGORITHM = "aes-256-gcm"
  NONCE_LENGTH = 12  # GCM standard
  TAG_LENGTH = 16    # GCM standard

  class << self
    extend T::Sig

    sig { params(plaintext: String).returns(String) }
    def encrypt(plaintext)
      cipher = OpenSSL::Cipher.new(ALGORITHM)
      cipher.encrypt
      cipher.key = encryption_key
      nonce = cipher.random_iv

      ciphertext = cipher.update(plaintext) + cipher.final
      tag = cipher.auth_tag(TAG_LENGTH)

      Base64.strict_encode64(nonce + ciphertext + tag)
    end

    sig { params(encoded: String).returns(String) }
    def decrypt(encoded)
      raw = Base64.strict_decode64(encoded)
      nonce = T.must(raw[0, NONCE_LENGTH])
      tag = T.must(raw[-TAG_LENGTH, TAG_LENGTH])
      ciphertext = T.must(raw[NONCE_LENGTH...-TAG_LENGTH])

      cipher = OpenSSL::Cipher.new(ALGORITHM)
      cipher.decrypt
      cipher.key = encryption_key
      cipher.iv = nonce
      cipher.auth_tag = tag

      cipher.update(ciphertext) + cipher.final
    end

    # Detect whether a value is encrypted (Base64-encoded with enough bytes for nonce + tag)
    sig { params(value: String).returns(T::Boolean) }
    def encrypted?(value)
      # Plaintext IBANs are alphanumeric (A-Z0-9), never contain + / =
      # Encrypted values are Base64 and always longer than raw IBANs
      return false if value.match?(/\A[A-Z]{2}\d{2}[A-Z0-9]{4,30}\z/)

      raw = Base64.strict_decode64(value)
      raw.bytesize > NONCE_LENGTH + TAG_LENGTH
    rescue ArgumentError
      false
    end

    private

    sig { returns(String) }
    def encryption_key
      # Derive a 32-byte key from APP_SECRET using HKDF
      OpenSSL::KDF.hkdf(
        APP_SECRET,
        salt: "tayaway-iban-encryption",
        info: "iban-aes-256-gcm",
        length: 32,
        hash: "SHA256"
      )
    end
  end
end
