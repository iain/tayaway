# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:task_items) do
      add_index :task_list_id # rubocop:disable Sequel/ConcurrentIndex
    end

    alter_table(:task_lists) do
      add_index :workspace_id # rubocop:disable Sequel/ConcurrentIndex
    end

    alter_table(:expenses) do
      add_index :event_id # rubocop:disable Sequel/ConcurrentIndex
    end

    alter_table(:settlements) do
      add_index :event_id # rubocop:disable Sequel/ConcurrentIndex
    end

    alter_table(:settlement_transfers) do
      add_index :settlement_id # rubocop:disable Sequel/ConcurrentIndex
    end
  end

  down do
    alter_table(:settlement_transfers) do
      drop_index :settlement_id # rubocop:disable Sequel/ConcurrentIndex
    end

    alter_table(:settlements) do
      drop_index :event_id # rubocop:disable Sequel/ConcurrentIndex
    end

    alter_table(:expenses) do
      drop_index :event_id # rubocop:disable Sequel/ConcurrentIndex
    end

    alter_table(:task_lists) do
      drop_index :workspace_id # rubocop:disable Sequel/ConcurrentIndex
    end

    alter_table(:task_items) do
      drop_index :task_list_id # rubocop:disable Sequel/ConcurrentIndex
    end
  end
end
