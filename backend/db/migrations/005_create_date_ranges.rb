# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
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
  end

  down do
    drop_table(:date_ranges)
  end
end
