# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:deleted_items) do
      add_index [:object_type, :object_id] # rubocop:disable Sequel/ConcurrentIndex
    end
  end

  down do
    alter_table(:deleted_items) do
      drop_index [:object_type, :object_id] # rubocop:disable Sequel/ConcurrentIndex
    end
  end
end
