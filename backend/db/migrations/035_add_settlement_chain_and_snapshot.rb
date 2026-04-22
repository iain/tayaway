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
  end
end
