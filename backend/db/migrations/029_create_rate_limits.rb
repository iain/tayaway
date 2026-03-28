# frozen_string_literal: true

Sequel.migration do
  up do
    create_table(:rate_limits) do
      String :key, null: false, primary_key: true
      Integer :count, null: false, default: 0
      DateTime :expires_at, null: false
    end
  end

  down do
    drop_table(:rate_limits)
  end
end
