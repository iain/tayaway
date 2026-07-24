# frozen_string_literal: true

# Read-only model for the passkeys enrolled on the admin site (doc/admin.md).
# Lives in the admin's own SQLite store, not the main database. One operator,
# one credential per device — the nickname is how devices are told apart.
class AdminCredential < Data.define(:id, :external_id, :nickname, :sign_count, :created_at, :last_used_at)
  class << self
    def all
      dataset.order(:created_at, :id).all
    end

    def find(id)
      dataset.where(id: id).first
    end

    private

    def dataset
      Admin::State.db[:admin_credentials].with_row_proc(method(:from_row))
    end

    def from_row(row)
      new(
        id: row[:id],
        external_id: row[:external_id],
        nickname: row[:nickname],
        sign_count: row[:sign_count],
        created_at: row[:created_at],
        last_used_at: row[:last_used_at]
      )
    end
  end
end
