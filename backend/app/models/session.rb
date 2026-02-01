# typed: true
# frozen_string_literal: true

require "securerandom"

class Session < Sequel::Model
  many_to_one :user

  SESSION_EXPIRY_DAYS = 30

  def self.create_for_user(user)
    create(
      user_id: user.id,
      token: SecureRandom.hex(32),
      expires_at: Time.now + (SESSION_EXPIRY_DAYS * 24 * 60 * 60)
    )
  end

  def self.find_valid_session(token)
    where(token: token)
      .where { expires_at > Time.now }
      .first
  end

  def valid?
    expires_at > Time.now
  end
end
