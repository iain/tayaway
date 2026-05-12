# frozen_string_literal: true

require "rbnacl"
require "openssl"
require "base64"

# libsodium encryption helper for sensitive fields stored on the users table.
#
# Stored format (v2): Base64(0x02 ‖ nonce ‖ ct+tag)
# Cipher: XChaCha20-Poly1305 AEAD with "user:<uuid>" as associated data,
# binding each ciphertext to its owning row.
module Encryption
  VERSION_2 = "\x02".b.freeze

  NONCE_BYTES = 24
  TAG_BYTES   = 16

  class << self
    def encrypt(plaintext, user_id:)
      nonce = RbNaCl::Random.random_bytes(NONCE_BYTES)
      ct = aead.encrypt(nonce, plaintext, aad_for(user_id))
      Base64.strict_encode64(VERSION_2 + nonce + ct)
    end

    def decrypt(encoded, user_id:)
      raw = Base64.strict_decode64(encoded)
      nonce = raw.byteslice(1, NONCE_BYTES)
      ct    = raw.byteslice((1 + NONCE_BYTES)..)
      aead.decrypt(nonce, ct, aad_for(user_id))
    end

    def encrypted?(value)
      raw = Base64.strict_decode64(value)
      raw.start_with?(VERSION_2) && raw.bytesize >= 1 + NONCE_BYTES + TAG_BYTES
    rescue ArgumentError
      false
    end

    private

    def aad_for(user_id)
      "user:#{user_id}"
    end

    def aead
      @_aead ||= RbNaCl::AEAD::XChaCha20Poly1305IETF.new(encryption_key)
    end

    def encryption_key
      OpenSSL::KDF.hkdf(
        APP_CONFIG.app_secret,
        salt: "tayaway-iban-encryption",
        info: "iban-nacl-secretbox",
        length: 32,
        hash: "SHA256"
      )
    end
  end
end
