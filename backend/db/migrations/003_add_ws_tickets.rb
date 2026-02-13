# typed: true
# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:ws_tickets) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      column :token, String, null: false, unique: true
      column :expires_at, :timestamptz, null: false
      column :used_at, :timestamptz
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :token
    end
  end
end
