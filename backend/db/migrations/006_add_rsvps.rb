# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:rsvps) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :event_id, :events, type: :uuid, null: false, on_delete: :cascade
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      column :attending, TrueClass, null: false
      column :start_date, Date
      column :end_date, Date
      column :created_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :updated_at, "timestamptz", null: false, default: Sequel.lit("NOW()")

      unique %i[event_id user_id]
      constraint(:valid_rsvp_date_range, Sequel.lit("start_date <= end_date"))
    end

    run <<~SQL
      CREATE TRIGGER update_rsvps_updated_at
        BEFORE UPDATE ON rsvps
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    SQL
  end

  down do
    drop_table(:rsvps)
  end
end
