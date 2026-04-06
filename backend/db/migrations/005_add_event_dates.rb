# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:events) do
      add_column :start_date, Date
      add_column :end_date, Date
    end

    run <<~SQL
      ALTER TABLE events
      ADD CONSTRAINT valid_event_date_range CHECK (start_date <= end_date)
    SQL
  end

  down do
    run <<~SQL
      ALTER TABLE events
      DROP CONSTRAINT IF EXISTS valid_event_date_range
    SQL

    alter_table(:events) do
      drop_column :end_date
      drop_column :start_date
    end
  end
end
