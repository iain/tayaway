# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:expense_participants) do
      column :id, :uuid, default: Sequel.lit("gen_random_uuid()"), null: false
      foreign_key :expense_id, :expenses, type: :uuid, null: false, on_delete: :cascade
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      column :created_at, "timestamptz", null: false, default: Sequel.lit("now()")

      primary_key [:id]
      unique [:expense_id, :user_id]
      index [:expense_id]
    end
  end
end
