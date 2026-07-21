# frozen_string_literal: true

# Sessions for the operator-only admin site (doc/admin.md). Deliberately a
# separate table from `sessions`: a much shorter TTL, never shown in the
# user-facing session list, and revocable independently of app sessions.
Sequel.migration do
  change do
    create_table(:admin_sessions) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade, on_update: :cascade
      String :token, null: false, unique: true, size: 64
      column :expires_at, :timestamptz, null: false
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :user_id
    end
  end
end
