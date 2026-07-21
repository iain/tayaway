# frozen_string_literal: true

# The admin site's own credential/session store (doc/admin.md). Lives in a
# SQLite file so operator login never depends on the Postgres database the
# dashboard exists to inspect.
Sequel.migration do
  change do
    create_table(:admin_credentials) do
      primary_key :id
      String :external_id, null: false, unique: true
      String :public_key, null: false
      Integer :sign_count, null: false, default: 0
      String :nickname, null: false
      Time :created_at, null: false
      Time :last_used_at
    end

    create_table(:admin_sessions) do
      primary_key :id
      String :token, null: false, unique: true
      foreign_key :credential_id, :admin_credentials, null: false, on_delete: :cascade
      Time :created_at, null: false
      Time :expires_at, null: false
    end
  end
end
