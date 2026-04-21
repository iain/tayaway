# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:settlements) do
      add_foreign_key :previous_settlement_id, :settlements, type: :uuid, null: true, on_delete: :set_null
      add_index :previous_settlement_id # rubocop:disable Sequel/ConcurrentIndex
      add_column :rsvp_snapshot, :jsonb, null: true
    end
  end
end
