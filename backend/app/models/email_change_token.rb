# frozen_string_literal: true

# Read-only email change token model.
class EmailChangeToken < Data.define(:id, :user_id, :token, :email, :new_email, :expires_at, :used_at, :created_at)
  EXPIRY_MINUTES = 15

  class << self
    def find(id)
      dataset.where(id: id).first
    end

    def find_valid(token, new_email)
      dataset
        .where(token: Auth::Token.digest(token), new_email: new_email)
        .where(used_at: nil)
        .where(Sequel[:expires_at] > Time.now)
        .first
    end

    private

    def from_row(row)
      new(
        id: UUID.new(row[:id]),
        user_id: UUID.new(row[:user_id]),
        token: row[:token],
        email: EmailAddress.new(row[:email]),
        new_email: EmailAddress.new(row[:new_email]),
        expires_at: row[:expires_at],
        used_at: row[:used_at],
        created_at: row[:created_at]
      )
    end

    def dataset
      DB[:email_change_tokens].with_row_proc(method(:from_row))
    end
  end
end
