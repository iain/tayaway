# typed: true
# frozen_string_literal: true

require "securerandom"

class MagicLinkToken < Sequel::Model
  many_to_one :user

  TOKEN_EXPIRY_MINUTES = 15

  def self.generate_for_user(user)
    create(
      user_id: user.id,
      token: SecureRandom.hex(32),
      email: user.email,
      expires_at: Time.now + (TOKEN_EXPIRY_MINUTES * 60)
    )
  end

  def self.find_valid_token(token, email)
    magic_token = where(token: token, email: email)
                  .where(used_at: nil)
                  .where { expires_at > Time.now }
                  .first

    return nil unless magic_token

    user = magic_token.user
    return nil unless user.email.downcase == email.downcase

    magic_token
  end

  def mark_used!
    update(used_at: Time.now)
  end

  def magic_link_url(frontend_url)
    "#{frontend_url}/auth/verify?token=#{token}&email=#{CGI.escape(email)}"
  end
end
