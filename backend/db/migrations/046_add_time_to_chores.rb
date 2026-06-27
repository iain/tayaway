# frozen_string_literal: true

# A chore can carry an optional wall-clock time of day. Combined with an
# assignment's date it gives the moment to remind the assigned person.
# Additive and nullable — existing chores stay timeless.
Sequel.migration do
  change do
    alter_table(:chores) do
      add_column :time, :time, null: true
    end
  end
end
