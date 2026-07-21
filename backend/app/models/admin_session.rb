# frozen_string_literal: true

# Read-only model for admin-site sessions (see doc/admin.md). Lives in the
# admin's own SQLite store, not the main database. Short-lived by design —
# the TTL is hours, not the days a regular Session gets.
class AdminSession < Data.define(:id, :credential_id, :token, :expires_at, :created_at)
  EXPIRY_SECONDS = 12 * 60 * 60 # 12 hours

  class << self
    def find_valid(token)
      dataset
        .where(token: Auth::Token.digest(token))
        .where(Sequel[:expires_at] > Time.now)
        .first
    end

    private

    def dataset
      Admin::State.db[:admin_sessions].with_row_proc(method(:from_row))
    end

    def from_row(row)
      new(
        id: row[:id],
        credential_id: row[:credential_id],
        token: row[:token],
        expires_at: row[:expires_at],
        created_at: row[:created_at]
      )
    end
  end
end
