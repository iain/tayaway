# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:users) do
      add_column :phone_number, :text
      add_column :birthday, :date
      add_column :location_name, :text
      add_column :location_coordinates, :point
    end
  end
end
