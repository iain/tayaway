# typed: true
# frozen_string_literal: true

# Read-only session model.
class Session < T::Struct
  extend T::Sig

  EXPIRY_DAYS = 30

  const :id, UUID
  const :user_id, UUID
  const :token, String
  const :expires_at, Time
  const :created_at, Time

  class << self
    extend T::Sig

    sig { params(token: String).returns(T.nilable(Session)) }
    def find_valid(token)
      dataset
        .where(token: token)
        .where(Sequel[:expires_at] > Time.now)
        .first
    end

    sig { params(token: String).returns(T.nilable(Session)) }
    def find_by_token(token)
      dataset.where(token: token).first
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:sessions].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(Session) }
    def from_row(row)
      Session.new(
        id: UUID.new(row[:id]),
        user_id: UUID.new(row[:user_id]),
        token: row[:token],
        expires_at: row[:expires_at],
        created_at: row[:created_at]
      )
    end
  end
end
