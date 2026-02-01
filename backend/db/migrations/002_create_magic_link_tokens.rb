# typed: true
# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:magic_link_tokens) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade, on_update: :cascade
      String :token, null: false, unique: true, size: 64
      column :email, :citext, null: false
      DateTime :expires_at, null: false
      DateTime :used_at
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :token
    end
  end
end
