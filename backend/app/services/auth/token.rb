# typed: true
# frozen_string_literal: true

require "openssl"
require "base64"
require "jwt"

module Auth
  module Token
    extend T::Sig

    sig { params(message: String).returns(String) }
    def self.digest(message)
      digest = OpenSSL::HMAC.digest("SHA3-512", APP_SECRET, message)
      Base64.urlsafe_encode64(digest[0, 32], padding: false)
    end

    sig { params(token: String, email: String).returns(String) }
    def self.encode_magic_link(token:, email:)
      payload = {
        token: token,
        email: email,
        typ: "magic_link",
        exp: (Time.now + (MagicLinkToken::EXPIRY_MINUTES * 60)).to_i
      }
      JWT.encode(payload, APP_SECRET, "HS256")
    end

    sig { params(jwt: String).returns(T::Hash[Symbol, String]) }
    def self.decode_magic_link(jwt)
      decoded = JWT.decode(jwt, APP_SECRET, true, algorithm: "HS256")
      payload = decoded.first
      raise JWT::DecodeError, "Invalid token type" unless payload["typ"] == "magic_link"

      { token: payload["token"], email: payload["email"] }
    end

    sig { params(token: String).returns(String) }
    def self.encode_ws_ticket(token:)
      payload = {
        token: token,
        typ: "ws_ticket",
        exp: (Time.now + WsTicket::EXPIRY_SECONDS).to_i
      }
      JWT.encode(payload, APP_SECRET, "HS256")
    end

    sig { params(jwt: String).returns(T::Hash[Symbol, String]) }
    def self.decode_ws_ticket(jwt)
      decoded = JWT.decode(jwt, APP_SECRET, true, algorithm: "HS256")
      payload = decoded.first
      raise JWT::DecodeError, "Invalid token type" unless payload["typ"] == "ws_ticket"

      { token: payload["token"] }
    end

    sig { params(token: String, email: String).returns(String) }
    def self.encode_invite(token:, email:)
      payload = {
        token: token,
        email: email,
        typ: "invite",
        exp: (Time.now + (WorkspaceInvite::EXPIRY_HOURS * 3600)).to_i
      }
      JWT.encode(payload, APP_SECRET, "HS256")
    end

    sig { params(jwt: String).returns(T::Hash[Symbol, String]) }
    def self.decode_invite(jwt)
      decoded = JWT.decode(jwt, APP_SECRET, true, algorithm: "HS256")
      payload = decoded.first
      raise JWT::DecodeError, "Invalid token type" unless payload["typ"] == "invite"

      { token: payload["token"], email: payload["email"] }
    end

    sig { params(token: String, email: String).returns(String) }
    def self.encode_email_change(token:, email:)
      payload = {
        token: token,
        email: email,
        typ: "email_change",
        exp: (Time.now + (EmailChangeToken::EXPIRY_MINUTES * 60)).to_i
      }
      JWT.encode(payload, APP_SECRET, "HS256")
    end

    sig { params(jwt: String).returns(T::Hash[Symbol, String]) }
    def self.decode_email_change(jwt)
      decoded = JWT.decode(jwt, APP_SECRET, true, algorithm: "HS256")
      payload = decoded.first
      raise JWT::DecodeError, "Invalid token type" unless payload["typ"] == "email_change"

      { token: payload["token"], email: payload["email"] }
    end
  end
end
