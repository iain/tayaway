# typed: true
# frozen_string_literal: true

require "openssl"
require "base64"

module Auth
  module Token
    extend T::Sig

    sig { params(message: String).returns(String) }
    def self.digest(message)
      digest = OpenSSL::HMAC.digest("SHA3-512", APP_SECRET, message)
      Base64.urlsafe_encode64(digest[0, 32], padding: false)
    end
  end
end
