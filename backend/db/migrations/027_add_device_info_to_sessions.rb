# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table :sessions do
      add_column :ip_address, :text
      add_column :city, :text
      add_column :country, :text
      add_column :browser_name, :text
      add_column :os_name, :text
    end
  end

  down do
    alter_table :sessions do
      drop_column :ip_address
      drop_column :city
      drop_column :country
      drop_column :browser_name
      drop_column :os_name
    end
  end
end
