# frozen_string_literal: true

# Read-only WebSocket ticket model.
class WsTicket < Data.define(:id, :session_id, :token, :expires_at, :used_at, :created_at)
  EXPIRY_SECONDS = 30

  class << self
    def find_valid(hashed_token)
      dataset
        .where(token: hashed_token)
        .where(used_at: nil)
        .where(Sequel[:expires_at] > Time.now)
        .first
    end

    private

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

    def dataset
      DB[:ws_tickets].with_row_proc(method(:from_row))
    end
  end
end
