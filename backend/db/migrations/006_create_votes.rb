# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
    # Create enum type for vote responses
    run "CREATE TYPE vote_response AS ENUM ('yes', 'no', 'preferably_not')"

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
  end

  down do
    drop_table(:votes)
    run "DROP TYPE vote_response"
  end
end
