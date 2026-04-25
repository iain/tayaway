# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:idempotency_keys) do
      String :idempotency_key, null: false
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      String :request_fingerprint, null: false
      Integer :response_status, null: false
      String :response_body, null: false, text: true
      DateTime :created_at, null: false

      primary_key %i[user_id idempotency_key]

      # Cleanup job filters by created_at; partial index keeps it small.
      index :created_at
    end
  end

  down do
    drop_table(:idempotency_keys)
  end
end
