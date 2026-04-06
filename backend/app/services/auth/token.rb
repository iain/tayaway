# frozen_string_literal: true

require "openssl"
require "base64"
require "jwt"

module Auth
  module Token
    def self.digest(message)
      digest = OpenSSL::HMAC.digest("SHA3-512", APP_SECRET, message)
      Base64.urlsafe_encode64(digest[0, 32], padding: false)
    end

    def self.encode_login_link(token:, email:)
      payload = {
        token: token,
        email: email,
        typ: "login_link",
        exp: (Time.now + (LoginLinkToken::EXPIRY_MINUTES * 60)).to_i
      }
      JWT.encode(payload, APP_SECRET, "HS256")
    end

    def self.decode_login_link(jwt)
      decoded = JWT.decode(jwt, APP_SECRET, true, algorithm: "HS256")
      payload = decoded.first
      raise JWT::DecodeError, "Invalid token type" unless payload["typ"] == "login_link"

      { token: payload["token"], email: payload["email"] }
    end

    def self.encode_ws_ticket(token:)
      payload = {
        token: token,
        typ: "ws_ticket",
        exp: (Time.now + WsTicket::EXPIRY_SECONDS).to_i
      }
      JWT.encode(payload, APP_SECRET, "HS256")
    end

    def self.decode_ws_ticket(jwt)
      decoded = JWT.decode(jwt, APP_SECRET, true, algorithm: "HS256")
      payload = decoded.first
      raise JWT::DecodeError, "Invalid token type" unless payload["typ"] == "ws_ticket"

      { token: payload["token"] }
    end

    def self.encode_invite(token:, email:)
      payload = {
        token: token,
        email: email,
        typ: "invite",
        exp: (Time.now + (WorkspaceInvite::EXPIRY_HOURS * 3600)).to_i
      }
      JWT.encode(payload, APP_SECRET, "HS256")
    end

    def self.decode_invite(jwt)
      decoded = JWT.decode(jwt, APP_SECRET, true, algorithm: "HS256")
      payload = decoded.first
      raise JWT::DecodeError, "Invalid token type" unless payload["typ"] == "invite"

      { token: payload["token"], email: payload["email"] }
    end

    def self.encode_email_change(token:, email:)
      payload = {
        token: token,
        email: email,
        typ: "email_change",
        exp: (Time.now + (EmailChangeToken::EXPIRY_MINUTES * 60)).to_i
      }
      JWT.encode(payload, APP_SECRET, "HS256")
    end

    def self.decode_email_change(jwt)
      decoded = JWT.decode(jwt, APP_SECRET, true, algorithm: "HS256")
      payload = decoded.first
      raise JWT::DecodeError, "Invalid token type" unless payload["typ"] == "email_change"

      { token: payload["token"], email: payload["email"] }
    end

    WEBAUTHN_CHALLENGE_EXPIRY_SECONDS = 300 # 5 minutes

    def self.encode_webauthn_challenge(challenge:, user_id: nil)
      typ = user_id ? "webauthn_register" : "webauthn_authenticate"
      payload = {
        challenge: challenge,
        typ: typ,
        exp: (Time.now + WEBAUTHN_CHALLENGE_EXPIRY_SECONDS).to_i
      }
      payload[:sub] = user_id if user_id
      JWT.encode(payload, APP_SECRET, "HS256")
    end

    def self.decode_webauthn_challenge(jwt, user_id: nil)
      decoded = JWT.decode(jwt, APP_SECRET, true, algorithm: "HS256")
      payload = decoded.first

      expected_typ = user_id ? "webauthn_register" : "webauthn_authenticate"
      raise JWT::DecodeError, "Invalid token type" unless payload["typ"] == expected_typ

      if user_id
        raise JWT::DecodeError, "Challenge missing subject" unless payload["sub"]
        raise JWT::DecodeError, "Challenge token was issued for a different user" unless payload["sub"] == user_id
      end

      { challenge: payload["challenge"] }
    end
  end
end
