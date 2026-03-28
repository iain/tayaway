# typed: true
# frozen_string_literal: true

# Read-only WebSocket ticket model.
class WsTicket < T::Struct
  extend T::Sig

  EXPIRY_SECONDS = 30

  const :id, UUID
  const :session_id, UUID
  const :token, String
  const :expires_at, Time
  const :used_at, T.nilable(Time)
  const :created_at, Time

  class << self
    extend T::Sig

    sig { params(hashed_token: String).returns(T.nilable(WsTicket)) }
    def find_valid(hashed_token)
      dataset
        .where(token: hashed_token)
        .where(used_at: nil)
        .where(Sequel[:expires_at] > Time.now)
        .first
    end

    private

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(WsTicket) }
    def from_row(row)
      new(
        id: UUID.new(row[:id]),
        session_id: UUID.new(row[:session_id]),
        token: row[:token],
        expires_at: row[:expires_at],
        used_at: row[:used_at],
        created_at: row[:created_at]
      )
    end

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:ws_tickets].with_row_proc(method(:from_row))
    end
  end
end
