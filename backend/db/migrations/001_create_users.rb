# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
    run "CREATE EXTENSION IF NOT EXISTS citext"

    create_table(:users) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      column :email, :citext, null: false, unique: true
      String :name
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end

  down do
    drop_table(:users)
  end
end
