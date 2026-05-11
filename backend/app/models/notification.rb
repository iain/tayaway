# frozen_string_literal: true

# In-app notification row. `data` is a kind-specific JSONB hash whose
# `title`, `body`, and `href` keys are rendered by the kind class at
# insert time so the frontend can list rows without per-kind logic.
class Notification < Data.define(:id, :user_id, :workspace_id, :kind, :data, :read_at, :created_at, :updated_at)
  def to_api_hash
    {
      id: id.to_s,
      objectType: "notification",
      userId: user_id.to_s,
      workspaceId: workspace_id&.to_s,
      kind: kind,
      data: data,
      readAt: read_at&.iso8601(3),
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    def find(id)
      dataset.where(id: id).first
    end

    def for_user(user_id, limit: 50)
      dataset
        .where(user_id: user_id)
        .order(Sequel.desc(:created_at))
        .limit(limit)
        .all
    end

    def unread_count_for_user(user_id)
      DB[:notifications].where(user_id: user_id, read_at: nil).count
    end

    # Marks one notification read and broadcasts the change so the user's
    # other devices/tabs pick up the new read_at without a refresh. The
    # `read_at: nil` predicate keeps the operation idempotent — re-reading
    # an already-read row updates nothing and broadcasts nothing.
    def mark_read(id, user_id:)
      affected = DB[:notifications]
                 .where(id: id, user_id: user_id, read_at: nil)
                 .returning(:id)
                 .update(read_at: Sequel::CURRENT_TIMESTAMP, updated_at: Sequel::CURRENT_TIMESTAMP)
      broadcast_changes(affected, user_id)
      affected.length
    end

    def mark_all_read(user_id)
      affected = DB[:notifications]
                 .where(user_id: user_id, read_at: nil)
                 .returning(:id)
                 .update(read_at: Sequel::CURRENT_TIMESTAMP, updated_at: Sequel::CURRENT_TIMESTAMP)
      broadcast_changes(affected, user_id)
      affected.length
    end

    private

    def broadcast_changes(rows, user_id)
      uid = user_id.to_s
      rows.each { |row| Broadcaster.object_changed("notification", row[:id], user_id: uid) }
    end

    def dataset
      DB[:notifications].with_row_proc(method(:from_row))
    end

    def from_row(row)
      new(
        id: row[:id],
        user_id: row[:user_id],
        workspace_id: row[:workspace_id],
        kind: row[:kind],
        data: row[:data],
        read_at: row[:read_at],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
