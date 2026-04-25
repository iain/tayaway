# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:idempotency_keys) do
      # SHA-256 hex of the client-supplied Idempotency-Key. We never need the
      # raw key back, only equality, so the digest keeps storage bounded
      # regardless of how long the client's key is.
      String :idempotency_key_hash, null: false, fixed: true, size: 64
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      String :request_fingerprint, null: false
      Integer :response_status, null: false
      String :response_body, null: false, text: true
      DateTime :created_at, null: false

      primary_key %i[user_id idempotency_key_hash]

      index :created_at
    end
  end

  down do
    drop_table(:idempotency_keys)
  end
end
