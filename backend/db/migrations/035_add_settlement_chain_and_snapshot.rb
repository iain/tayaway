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
      # At most one root per event. Combined with the lock in Settlements::Create,
      # this makes a forked chain impossible even under a concurrent race.
      add_index :event_id, # rubocop:disable Sequel/ConcurrentIndex
                unique: true,
                name: :settlements_root_per_event_unique,
                where: Sequel.lit("previous_settlement_id IS NULL")
      add_column :rsvp_snapshot, :jsonb, null: true
    end

    alter_table(:expenses) do
      # Nullable self-reference so the UI can show "reverts expense X" and
      # mark the original as reverted. on_delete: :set_null so an original
      # being hard-deleted out of band doesn't orphan the revert's ledger
      # contribution.
      add_foreign_key :reverts_expense_id, :expenses, type: :uuid, null: true, on_delete: :set_null
      # Unique partial index prevents two concurrent revert attempts from both
      # landing a mirror-image expense on the same original.
      add_index :reverts_expense_id, # rubocop:disable Sequel/ConcurrentIndex
                unique: true,
                where: Sequel.lit("reverts_expense_id IS NOT NULL")
    end
  end
end
