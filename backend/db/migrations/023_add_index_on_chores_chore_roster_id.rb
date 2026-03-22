# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:chores) do
      add_index :chore_roster_id # rubocop:disable Sequel/ConcurrentIndex
    end
  end

  down do
    alter_table(:chores) do
      drop_index :chore_roster_id # rubocop:disable Sequel/ConcurrentIndex
    end
  end
end
