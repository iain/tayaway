# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:workspace_invites) do
      add_column :last_reminded_at, :timestamptz, null: true
    end
  end
end
