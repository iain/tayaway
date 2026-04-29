# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:settlement_transfers) do
      # Records who actually clicked "Mark as paid". Either party (sender or
      # recipient) can attest, so the column tells the audit log and the UI
      # which side closed the loop. NULL on rows marked paid before this
      # column existed and on rows that aren't paid yet.
      add_foreign_key :paid_by_user_id, :users, type: :uuid, null: true, on_delete: :set_null
    end
  end
end
