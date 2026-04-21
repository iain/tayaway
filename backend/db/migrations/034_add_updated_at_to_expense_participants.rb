# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:expense_participants) do
      add_column :updated_at, "timestamptz", null: false, default: Sequel.lit("now()")
    end
  end
end
