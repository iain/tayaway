# frozen_string_literal: true

# Deploy M of doc/attendances.md phase 8: guest attendances may now hold
# chore assignments, so user_id (the mirrored member column) becomes
# nullable. Dropping NOT NULL is metadata-only and safe pre-restart — the
# still-running deploy-N code writes user_id on every insert.
Sequel.migration do
  up do
    alter_table(:chore_assignments) do
      set_column_allow_null :user_id
    end

    # Re-run the 052 attendance_id backfill to catch rows written by
    # pre-052 code during that deploy's migration→restart window. Deploy-N
    # code always writes attendance_id, so after this every row resolves.
    run <<~SQL
      INSERT INTO attendances (id, event_id, user_id, status, created_at, updated_at)
      SELECT gen_random_uuid(), missing.event_id, missing.user_id, 'pending', NOW(), NOW()
      FROM (
        SELECT DISTINCT cr.event_id, ca.user_id
        FROM chore_assignments ca
        JOIN chores c ON c.id = ca.chore_id
        JOIN chore_rosters cr ON cr.id = c.chore_roster_id
        LEFT JOIN attendances a ON a.event_id = cr.event_id AND a.user_id = ca.user_id
        WHERE ca.attendance_id IS NULL AND a.id IS NULL
      ) missing
    SQL

    run <<~SQL
      UPDATE chore_assignments ca
      SET attendance_id = a.id
      FROM chores c
      JOIN chore_rosters cr ON cr.id = c.chore_roster_id
      JOIN attendances a ON a.event_id = cr.event_id
      WHERE c.id = ca.chore_id
        AND a.user_id = ca.user_id
        AND ca.attendance_id IS NULL
    SQL
  end

  down do
    # Guest rows (user_id NULL) block re-adding NOT NULL; remove them first —
    # they cannot be represented in the pre-guest schema.
    run "DELETE FROM chore_assignments WHERE user_id IS NULL"
    alter_table(:chore_assignments) do
      set_column_not_null :user_id
    end
  end
end
