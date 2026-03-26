# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:ws_tickets) do
      add_column :session_id, :uuid
      add_foreign_key [:session_id], :sessions, on_delete: :set_null
    end
  end
end
