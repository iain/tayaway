# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:task_lists) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :workspace_id, :workspaces, type: :uuid, null: false, on_delete: :cascade
      foreign_key :user_id, :users, type: :uuid, null: true, on_delete: :set_null
      column :name, String, null: false
      column :created_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :updated_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
    end

    run <<~SQL
      CREATE TRIGGER update_task_lists_updated_at
        BEFORE UPDATE ON task_lists
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    SQL

    create_table(:task_items) do
      column :id, :uuid, primary_key: true, default: Sequel.lit("gen_random_uuid()")
      foreign_key :task_list_id, :task_lists, type: :uuid, null: false, on_delete: :cascade
      foreign_key :user_id, :users, type: :uuid, null: true, on_delete: :set_null
      column :content, String, null: false
      column :completed_at, "timestamptz"
      column :created_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
      column :updated_at, "timestamptz", null: false, default: Sequel.lit("NOW()")
    end

    run <<~SQL
      CREATE TRIGGER update_task_items_updated_at
        BEFORE UPDATE ON task_items
        FOR EACH ROW
        EXECUTE FUNCTION update_updated_at_column();
    SQL
  end

  down do
    drop_table(:task_items)
    drop_table(:task_lists)
  end
end
