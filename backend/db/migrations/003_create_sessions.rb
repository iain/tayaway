# typed: true
# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:sessions) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade, on_update: :cascade
      String :token, null: false, unique: true, size: 64
      DateTime :expires_at, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :token
      index :user_id
    end
  end
end
