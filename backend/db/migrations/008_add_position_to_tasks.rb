# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:task_lists) do
      add_column :position, Float, null: false, default: 0.0
    end

    alter_table(:task_items) do
      add_column :position, Float, null: false, default: 0.0
    end

    run(<<~SQL)
      UPDATE task_lists SET position = sub.rn
      FROM (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY workspace_id ORDER BY created_at)::float AS rn
        FROM task_lists
      ) sub WHERE task_lists.id = sub.id;

      UPDATE task_items SET position = sub.rn
      FROM (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY task_list_id ORDER BY created_at)::float AS rn
        FROM task_items
      ) sub WHERE task_items.id = sub.id;
    SQL
  end

  down do
    alter_table(:task_lists) { drop_column :position }
    alter_table(:task_items) { drop_column :position }
  end
end
