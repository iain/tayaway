# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:deleted_items) do
      add_column :deleted_by, :uuid, null: true
    end
  end
end
