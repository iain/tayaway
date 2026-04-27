# frozen_string_literal: true

# Read-only login link token model.
class LoginLinkToken < Data.define(:id, :user_id, :token, :email, :expires_at, :used_at, :created_at)
  EXPIRY_MINUTES = 15

  class << self
    def find(id)
      dataset.where(id: id).first
    end

    def find_valid(token, email)
      record = dataset
               .where(token: Auth::Token.digest(token), email: email)
               .where(used_at: nil)
               .where(Sequel[:expires_at] > Time.now)
               .first

      return nil unless record

      user = User.find(record.user_id)
      return nil unless user
      return nil unless user.email.to_s.downcase == email.downcase

      record
    end

    private

    def from_row(row)
      new(
        id: UUID.new(row[:id]),
        user_id: UUID.new(row[:user_id]),
        token: row[:token],
        email: EmailAddress.new(row[:email]),
        expires_at: row[:expires_at],
        used_at: row[:used_at],
        created_at: row[:created_at]
      )
    end

    def dataset
      DB[:login_link_tokens].with_row_proc(method(:from_row))
    end
  end
end
