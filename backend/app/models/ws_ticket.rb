# frozen_string_literal: true

# Read-only WebSocket ticket model.
class WsTicket
  EXPIRY_SECONDS = 30

  attr_reader :id, :session_id, :token, :expires_at, :used_at, :created_at

  def initialize(id:, session_id:, token:, expires_at:, used_at:, created_at:)
    @id = id
    @session_id = session_id
    @token = token
    @expires_at = expires_at
    @used_at = used_at
    @created_at = created_at
  end

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
