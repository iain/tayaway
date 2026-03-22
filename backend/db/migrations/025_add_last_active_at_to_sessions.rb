# typed: true
# frozen_string_literal: true

Sequel.migration do
  up do
    add_column :sessions, :last_active_at, :timestamptz
  end

  down do
    drop_column :sessions, :last_active_at
  end
end
