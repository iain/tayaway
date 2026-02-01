# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:events) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      String :name, null: false, size: 255
      String :description, text: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :user_id
    end
  end

  down do
    drop_table(:events)
  end
end
