# frozen_string_literal: true

# rubocop:disable Sequel/ConcurrentIndex
Sequel.migration do
  up do
    # Create date_polls table
    create_table(:date_polls) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :event_id, :events, type: :uuid, null: false, unique: true, on_delete: :cascade
      column :deadline, :timestamptz, null: false
      foreign_key :selected_date_range_id, :date_ranges, type: :uuid, on_delete: :set_null
      column :closed_at, :timestamptz
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Add trigger for date_polls updated_at
    run <<~SQL
      CREATE TRIGGER update_date_polls_updated_at
      BEFORE UPDATE ON date_polls
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL

    # Add date_poll_id to date_ranges (initially nullable)
    alter_table(:date_ranges) do
      add_column :date_poll_id, :uuid
    end

    # Migrate existing date_ranges: create a date_poll per event that has date_ranges
    run <<~SQL
      INSERT INTO date_polls (id, event_id, deadline, created_at, updated_at)
      SELECT DISTINCT
        gen_random_uuid(),
        event_id,
        NOW() + INTERVAL '7 days',
        NOW(),
        NOW()
      FROM date_ranges
    SQL

    # Link existing date_ranges to their event's date_poll
    run <<~SQL
      UPDATE date_ranges
      SET date_poll_id = date_polls.id
      FROM date_polls
      WHERE date_ranges.event_id = date_polls.event_id
    SQL

    # Make date_poll_id NOT NULL and add FK
    alter_table(:date_ranges) do
      set_column_not_null :date_poll_id
      add_foreign_key [:date_poll_id], :date_polls, key: :id, on_delete: :cascade

      # Drop old event_id column and its indexes
      drop_index :event_id, if_exists: true
      drop_index [:event_id, :start_date], if_exists: true
      drop_column :event_id

      # Add new indexes on date_poll_id
      add_index :date_poll_id
      add_index [:date_poll_id, :start_date]
    end
  end

  down do
    # Re-add event_id to date_ranges
    alter_table(:date_ranges) do
      add_column :event_id, :uuid
    end

    # Restore event_id from date_poll
    run <<~SQL
      UPDATE date_ranges
      SET event_id = date_polls.event_id
      FROM date_polls
      WHERE date_ranges.date_poll_id = date_polls.id
    SQL

    alter_table(:date_ranges) do
      set_column_not_null :event_id
      add_foreign_key [:event_id], :events, key: :id, on_delete: :cascade

      drop_index :date_poll_id, if_exists: true
      drop_index [:date_poll_id, :start_date], if_exists: true
      drop_column :date_poll_id

      add_index :event_id
      add_index [:event_id, :start_date]
    end

    run "DROP TRIGGER IF EXISTS update_date_polls_updated_at ON date_polls"
    drop_table(:date_polls)
  end
end
# rubocop:enable Sequel/ConcurrentIndex
