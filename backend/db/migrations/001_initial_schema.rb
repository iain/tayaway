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

    # Create enum types
    run "CREATE TYPE vote_response AS ENUM ('yes', 'no', 'preferably_not')"
    run "CREATE TYPE workspace_role AS ENUM ('owner', 'admin', 'member')"

    # Users table
    create_table(:users) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      column :email, :citext, null: false, unique: true
      String :name
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Add trigger for users updated_at
    run <<~SQL
      CREATE TRIGGER update_users_updated_at
      BEFORE UPDATE ON users
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL

    # Workspaces table
    create_table(:workspaces) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      String :name, null: false, size: 255
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Add trigger for workspaces updated_at
    run <<~SQL
      CREATE TRIGGER update_workspaces_updated_at
      BEFORE UPDATE ON workspaces
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL

    # Workspace memberships (users can belong to many workspaces)
    create_table(:workspace_memberships) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :workspace_id, :workspaces, type: :uuid, null: false, on_delete: :cascade
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      column :role, :workspace_role, null: false, default: "member"
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP

      index [:workspace_id, :user_id], unique: true
      index :user_id
    end

    # Add trigger for workspace_memberships updated_at
    run <<~SQL
      CREATE TRIGGER update_workspace_memberships_updated_at
      BEFORE UPDATE ON workspace_memberships
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL

    # Magic link tokens table
    create_table(:magic_link_tokens) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade, on_update: :cascade
      String :token, null: false, unique: true, size: 64
      column :email, :citext, null: false
      column :expires_at, :timestamptz, null: false
      column :used_at, :timestamptz
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :token
    end

    # Add trigger for magic_link_tokens updated_at
    run <<~SQL
      CREATE TRIGGER update_magic_link_tokens_updated_at
      BEFORE UPDATE ON magic_link_tokens
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL

    # Sessions table
    create_table(:sessions) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade, on_update: :cascade
      String :token, null: false, unique: true, size: 64
      column :expires_at, :timestamptz, null: false
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      index :token
      index :user_id
    end

    # Add trigger for sessions updated_at
    run <<~SQL
      CREATE TRIGGER update_sessions_updated_at
      BEFORE UPDATE ON sessions
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
    SQL

    # Events table
    create_table(:events) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :workspace_id, :workspaces, type: :uuid, null: false, on_delete: :cascade
      foreign_key :user_id, :users, type: :uuid, on_delete: :set_null
      String :name, null: false, size: 255
      String :description, text: true
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :workspace_id
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
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP

      constraint(:valid_date_range, Sequel.lit("start_date <= end_date"))
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
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP

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
    drop_table(:workspace_memberships)
    drop_table(:workspaces)
    drop_table(:sessions)
    drop_table(:magic_link_tokens)
    drop_table(:users)

    run "DROP TYPE vote_response"
    run "DROP TYPE workspace_role"
    run "DROP FUNCTION update_updated_at_column"
  end
end
