# frozen_string_literal: true

Sequel.migration do
  up do
    # Step 1: Add nullable columns
    add_column :expenses, :start_date, :date
    add_column :expenses, :end_date, :date

    # Step 2: Backfill from event dates where available
    run <<~SQL
      UPDATE expenses
      SET start_date = events.start_date, end_date = events.end_date
      FROM events
      WHERE expenses.event_id = events.id
        AND events.start_date IS NOT NULL
        AND events.end_date IS NOT NULL
    SQL

    # Step 3: Fallback for expenses on events without dates
    run <<~SQL
      UPDATE expenses
      SET start_date = CURRENT_DATE, end_date = CURRENT_DATE
      WHERE start_date IS NULL
    SQL

    # Step 4: Make NOT NULL and add constraint
    alter_table(:expenses) do
      set_column_not_null :start_date
      set_column_not_null :end_date
      add_constraint(:expenses_date_range, Sequel.lit("start_date <= end_date"))
    end
  end

  down do
    alter_table(:expenses) do
      drop_constraint(:expenses_date_range)
      drop_column :start_date
      drop_column :end_date
    end
  end
end
