# frozen_string_literal: true

Sequel.migration do
  up do
    # Delete all sessions so existing ws_tickets (which may lack session_id) are
    # cascade-deleted. Users will need to log in again after this deploy.
    run "DELETE FROM sessions"

    alter_table(:ws_tickets) do
      # Drop the user_id column — the session already references the user
      drop_foreign_key [:user_id]
      drop_column :user_id

      # Add session_id as a required FK with cascade delete
      add_column :session_id, :uuid, null: false
      add_foreign_key [:session_id], :sessions, on_delete: :cascade
    end
  end

  down do
    alter_table(:ws_tickets) do
      drop_foreign_key [:session_id]
      drop_column :session_id

      add_column :user_id, :uuid, null: false
      add_foreign_key [:user_id], :users, on_delete: :cascade
    end
  end
end
