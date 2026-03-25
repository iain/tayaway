# typed: false
# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:audit_logs) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), null: false
      foreign_key :user_id, :users, type: :uuid, null: true, on_delete: :set_null
      column :action, :text, null: false
      column :object_type, :text, null: false
      column :object_id, :uuid, null: false
      column :workspace_id, :uuid, null: true
      column :metadata, :jsonb, null: true
      column :created_at, "timestamptz", null: false, default: Sequel.lit("now()")

      primary_key [:id]
      index [:object_type, :object_id]
      index [:user_id, :created_at]
    end
  end
end
