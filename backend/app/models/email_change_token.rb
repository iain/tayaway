# typed: true
# frozen_string_literal: true

# Read-only email change token model.
class EmailChangeToken < T::Struct
  extend T::Sig

  EXPIRY_MINUTES = 15

  const :id, UUID
  const :user_id, UUID
  const :token, String
  const :email, EmailAddress
  const :new_email, EmailAddress
  const :expires_at, Time
  const :used_at, T.nilable(Time)
  const :created_at, Time

  class << self
    extend T::Sig

    sig { params(id: T.any(UUID, String)).returns(T.nilable(EmailChangeToken)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(token: String, new_email: String).returns(T.nilable(EmailChangeToken)) }
    def find_valid(token, new_email)
      dataset
        .where(token: Auth::Token.digest(token), new_email: new_email)
        .where(used_at: nil)
        .where(Sequel[:expires_at] > Time.now)
        .first
    end

    private

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(EmailChangeToken) }
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

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:email_change_tokens].with_row_proc(method(:from_row))
    end
  end
end
