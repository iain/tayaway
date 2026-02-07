# typed: true
# frozen_string_literal: true

# Read-only magic link token model.
class MagicLinkToken < T::Struct
  extend T::Sig

  EXPIRY_MINUTES = 15

  const :id, UUID
  const :user_id, UUID
  const :token, String
  const :email, EmailAddress
  const :expires_at, Time
  const :used_at, T.nilable(Time)
  const :created_at, Time

  class << self
    extend T::Sig

    sig { params(token: String, email: String).returns(T.nilable(MagicLinkToken)) }
    def find_valid(token, email)
      row = DB[:magic_link_tokens]
        .where(token: token, email: email)
        .where(used_at: nil)
        .where(Sequel[:expires_at] > Time.now)
        .first

      return nil unless row

      user = User.find(row[:user_id])
      return nil unless user
      return nil unless user.email.to_s.downcase == email.downcase

      from_row(row)
    end

    private

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(MagicLinkToken) }
    def from_row(row)
      MagicLinkToken.new(
        id: UUID.new(row[:id]),
        user_id: UUID.new(row[:user_id]),
        token: row[:token],
        email: EmailAddress.new(row[:email]),
        expires_at: row[:expires_at],
        used_at: row[:used_at],
        created_at: row[:created_at]
      )
    end
  end
end
