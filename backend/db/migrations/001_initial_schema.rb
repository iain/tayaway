# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
    # Enable extensions
    run "CREATE EXTENSION IF NOT EXISTS citext"

    # Create trigger function for automatically updating updated_at
    run <<~SQL
      CREATE OR REPLACE FUNCTION update_updated_at_column()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
      END;
      $$ language 'plpgsql';
    SQL

    # Create enum type for vote responses
    run "CREATE TYPE vote_response AS ENUM ('yes', 'no', 'preferably_not')"

    # Users table
    create_table(:users) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      column :email, :citext, null: false, unique: true
      String :name
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Magic link tokens table
    create_table(:magic_link_tokens) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade, on_update: :cascade
      String :token, null: false, unique: true, size: 64
      column :email, :citext, null: false
      DateTime :expires_at, null: false
      DateTime :used_at
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :token
    end

    # Sessions table
    create_table(:sessions) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade, on_update: :cascade
      String :token, null: false, unique: true, size: 64
      DateTime :expires_at, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :token
      index :user_id
    end

    # Events table
    create_table(:events) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      String :name, null: false, size: 255
      String :description, text: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :user_id
    end

    # Add trigger for events updated_at
    run <<~SQL
      CREATE TRIGGER update_events_updated_at
      BEFORE UPDATE ON events
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL

    # Date ranges table
    create_table(:date_ranges) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :event_id, :events, type: :uuid, null: false, on_delete: :cascade
      Date :start_date, null: false
      Date :end_date, null: false
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :event_id
      index [:event_id, :start_date]
    end

    # Add trigger for date_ranges updated_at
    run <<~SQL
      CREATE TRIGGER update_date_ranges_updated_at
      BEFORE UPDATE ON date_ranges
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL

    # Votes table
    create_table(:votes) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :date_range_id, :date_ranges, type: :uuid, null: false, on_delete: :cascade
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      column :response, :vote_response, null: false
      String :comment, text: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index [:date_range_id, :user_id], unique: true
      index :user_id
    end

    # Add trigger for votes updated_at
    run <<~SQL
      CREATE TRIGGER update_votes_updated_at
      BEFORE UPDATE ON votes
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL
  end

  down do
    drop_table(:votes)
    drop_table(:date_ranges)
    drop_table(:events)
    drop_table(:sessions)
    drop_table(:magic_link_tokens)
    drop_table(:users)

    run "DROP TYPE vote_response"
    run "DROP FUNCTION update_updated_at_column"
  end
end
