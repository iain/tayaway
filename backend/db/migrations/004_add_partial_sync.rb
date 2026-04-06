# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:deleted_items) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      column :workspace_id, :uuid, null: false
      String :object_type, null: false
      column :object_id, :uuid, null: false
      column :deleted_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP

      index [:workspace_id, :deleted_at]
    end
  end

  down do
    drop_table(:deleted_items)
  end
end
