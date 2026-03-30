# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:passkey_credentials) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), primary_key: true
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      column :external_id, String, null: false
      column :public_key, String, null: false
      column :sign_count, Integer, null: false, default: 0
      column :aaguid, String
      column :name, String
      column :created_at, :timestamptz, null: false, default: Sequel.lit("NOW()")

      unique :external_id
      index :user_id
    end
  end

  down do
    drop_table(:passkey_credentials)
  end
end
