# frozen_string_literal: true

require "rbnacl"
require "openssl"
require "base64"

# libsodium encryption helper for sensitive fields stored on the users table.
#
# Format history:
#   Legacy unversioned: Base64(nonce ‖ mac ‖ ct)          — XSalsa20-Poly1305, no AAD
#   v1:                 Base64(0x01 ‖ nonce ‖ mac ‖ ct)   — same crypto, version-tagged
#   v2:                 Base64(0x02 ‖ nonce ‖ ct+tag)     — XChaCha20-Poly1305 AEAD, user_id as AAD
#
# Writes always emit v2. Reads accept v1 and v2.
module Encryption
  VERSION_1 = "\x01".b.freeze
  VERSION_2 = "\x02".b.freeze

  NONCE_BYTES = 24
  TAG_BYTES   = 16
  MIN_ENCRYPTED_BYTES = NONCE_BYTES + TAG_BYTES # 40

  class << self
    def encrypt(plaintext, user_id:)
      nonce = RbNaCl::Random.random_bytes(NONCE_BYTES)
      ct = aead.encrypt(nonce, plaintext, aad_for(user_id))
      Base64.strict_encode64(VERSION_2 + nonce + ct)
    end

    # v1 format for the backfill migration only — not for application use.
    def encrypt_v1(plaintext)
      raw = box.box(plaintext)
      Base64.strict_encode64(VERSION_1 + raw)
    end

    def decrypt(encoded, user_id:)
      raw = Base64.strict_decode64(encoded)

      if raw.start_with?(VERSION_2)
        nonce = raw.byteslice(1, NONCE_BYTES)
        ct    = raw.byteslice((1 + NONCE_BYTES)..)
        aead.decrypt(nonce, ct, aad_for(user_id))
      elsif raw.start_with?(VERSION_1)
        box.open(raw.byteslice(1..))
      else
        box.open(raw)
      end
    end

    def encrypted?(value)
      raw = Base64.strict_decode64(value)

      if raw.start_with?(VERSION_2, VERSION_1)
        raw.bytesize >= 1 + MIN_ENCRYPTED_BYTES
      else
        raw.bytesize >= MIN_ENCRYPTED_BYTES
      end
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
