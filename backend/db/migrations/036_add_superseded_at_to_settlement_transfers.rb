# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:settlement_transfers) do
      # When a top-up happens, any unpaid prior transfers no longer represent
      # the real obligation — the new settlement's transfers supersede them.
      # Paid transfers are sunk money and never superseded.
      add_column :superseded_at, :timestamptz, null: true
    end
  end
end
