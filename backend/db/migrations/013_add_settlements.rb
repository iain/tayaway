# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:settlements) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :event_id, :events, type: :uuid, null: false, on_delete: :cascade
      foreign_key :user_id, :users, type: :uuid, null: true, on_delete: :set_null
      column :created_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :updated_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
    end

    create_table(:settlement_transfers) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :settlement_id, :settlements, type: :uuid, null: false, on_delete: :cascade
      foreign_key :from_user_id, :users, type: :uuid, null: true, on_delete: :set_null
      foreign_key :to_user_id, :users, type: :uuid, null: true, on_delete: :set_null
      column :amount, :numeric, null: false
      column :paid_at, "timestamptz"
      column :created_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :updated_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
    end

    alter_table(:expenses) do
      add_foreign_key :settlement_id, :settlements, type: :uuid, null: true, on_delete: :set_null
      add_index :settlement_id # rubocop:disable Sequel/ConcurrentIndex
    end

    run <<~SQL
      CREATE TRIGGER update_settlements_updated_at
        BEFORE UPDATE ON settlements
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    SQL

    run <<~SQL
      CREATE TRIGGER update_settlement_transfers_updated_at
        BEFORE UPDATE ON settlement_transfers
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    SQL
  end

  down do
    alter_table(:expenses) do
      drop_foreign_key :settlement_id
    end
    drop_table(:settlement_transfers)
    drop_table(:settlements)
  end
end
