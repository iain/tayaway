# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:chore_rosters) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :event_id, :events, type: :uuid, null: false, unique: true, on_delete: :cascade
      foreign_key :user_id, :users, type: :uuid, null: true, on_delete: :set_null
      column :created_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :updated_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
    end

    create_table(:chores) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :chore_roster_id, :chore_rosters, type: :uuid, null: false, on_delete: :cascade
      column :name, String, size: 255, null: false
      column :people_per_day, :integer, null: false, default: 1
      column :position, :float, null: false, default: 0.0
      column :created_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :updated_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
    end

    create_table(:chore_assignments) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :chore_id, :chores, type: :uuid, null: false, on_delete: :cascade
      foreign_key :user_id, :users, type: :uuid, null: false, on_delete: :cascade
      column :date, :date, null: false
      column :pinned, :boolean, null: false, default: false
      column :note, :text
      column :created_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :updated_at, "timestamptz", null: false, default: Sequel.lit("NOW()")

      unique [:chore_id, :user_id, :date]
    end

    run <<~SQL
      CREATE TRIGGER update_chore_rosters_updated_at
        BEFORE UPDATE ON chore_rosters
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    SQL

    run <<~SQL
      CREATE TRIGGER update_chores_updated_at
        BEFORE UPDATE ON chores
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    SQL

    run <<~SQL
      CREATE TRIGGER update_chore_assignments_updated_at
        BEFORE UPDATE ON chore_assignments
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    SQL
  end

  down do
    drop_table(:chore_assignments)
    drop_table(:chores)
    drop_table(:chore_rosters)
  end
end
