# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:expense_participants) do
      add_column :factor, "numeric(6,3)", null: false, default: 1
      add_constraint(:expense_participants_factor_positive, Sequel.lit("factor > 0"))
    end
  end
end
