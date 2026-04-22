# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table(:settlements) do
      # on_delete: :restrict so a mid-chain row can't be detached at the DB
      # layer — the top-up that references it relies on its rsvp_snapshot.
      add_foreign_key :previous_settlement_id, :settlements, type: :uuid, null: true, on_delete: :restrict
      # Unique partial index enforces the "at most one successor per parent"
      # invariant structurally, so a concurrent top-up can't fork the chain.
      add_index :previous_settlement_id, # rubocop:disable Sequel/ConcurrentIndex
                unique: true,
                where: Sequel.lit("previous_settlement_id IS NOT NULL")
      add_column :rsvp_snapshot, :jsonb, null: true
    end

    alter_table(:expenses) do
      # Nullable self-reference so the UI can show "reverts expense X" and
      # mark the original as reverted. on_delete: :set_null so an original
      # being hard-deleted out of band doesn't orphan the revert's ledger
      # contribution.
      add_foreign_key :reverts_expense_id, :expenses, type: :uuid, null: true, on_delete: :set_null
      add_index :reverts_expense_id # rubocop:disable Sequel/ConcurrentIndex
    end
  end
end
