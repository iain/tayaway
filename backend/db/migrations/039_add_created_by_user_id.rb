# frozen_string_literal: true

# Track who actually filed an RSVP or expense, separately from whose record
# it is. Pre-existing rows backfill from `user_id` since the actor and
# subject were always the same before this column existed.
Sequel.migration do
  up do
    alter_table(:expenses) do
      add_foreign_key :created_by_user_id, :users, type: :uuid, null: true
    end
    alter_table(:rsvps) do
      add_foreign_key :created_by_user_id, :users, type: :uuid, null: true
    end

    run "UPDATE expenses SET created_by_user_id = user_id WHERE created_by_user_id IS NULL"
    run "UPDATE rsvps SET created_by_user_id = user_id WHERE created_by_user_id IS NULL"
  end

  down do
    alter_table(:expenses) { drop_foreign_key :created_by_user_id }
    alter_table(:rsvps) { drop_foreign_key :created_by_user_id }
  end
end
