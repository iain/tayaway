# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:events) do
      add_column :location_name, :text
      add_column :location_coordinates, :point
    end
  end
end
