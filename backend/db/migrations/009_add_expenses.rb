# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:expenses) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :event_id, :events, type: :uuid, null: false, on_delete: :cascade
      foreign_key :user_id, :users, type: :uuid, null: true, on_delete: :set_null
      column :amount, :numeric, null: false
      column :description, String, null: false
      column :created_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :updated_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
    end

    run <<~SQL
      CREATE TRIGGER update_expenses_updated_at
        BEFORE UPDATE ON expenses
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    SQL
  end

  down do
    drop_table(:expenses)
  end
end
