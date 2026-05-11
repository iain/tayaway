# frozen_string_literal: true

# Per-user notification rows backing the in-app inbox. `kind` mirrors the
# notification kind in the registry; `data` is a kind-specific JSONB blob
# rendered server-side (title/body/href) so the frontend just lists what
# it gets without per-kind logic. `workspace_id` is metadata for filtering
# and link targets, not used for routing — notifications belong to a
# user, not a workspace.
Sequel.migration do
  up do
    create_table(:notifications) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      foreign_key :workspace_id, :workspaces, type: :uuid, on_delete: :cascade
      String :kind, null: false, text: true
      jsonb :data, null: false, default: "{}"
      column :read_at, :timestamptz
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Inbox listing — newest first, per user.
    run "CREATE INDEX notifications_inbox ON notifications (user_id, created_at DESC)"

    # Unread badge — partial index keeps the unread set tight even as
    # read history grows.
    run "CREATE INDEX notifications_unread ON notifications (user_id) WHERE read_at IS NULL"

    run <<~SQL
      CREATE TRIGGER update_notifications_updated_at
      BEFORE UPDATE ON notifications
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL
  end

  down do
    drop_table(:notifications)
  end
end
