# frozen_string_literal: true

# Chore assignments learn to reference the attendance row behind the holder
# (doc/attendances.md phase 8): presence-side tables point at attendances via
# a single FK, never at their own user/guest pair. Additive — user_id stays
# populated (and NOT NULL) for old clients until the later deploys; from this
# deploy on the services dual-write both columns.
Sequel.migration do
  up do
    alter_table(:chore_assignments) do
      # CASCADE mirrors the existing user_id cascade: an attendance row is
      # only ever hard-deleted via an event/user deletion cascade, where the
      # assignment must die with it (attendance rows otherwise transition
      # status instead of being deleted).
      add_foreign_key :attendance_id, :attendances, type: :uuid, on_delete: :cascade
      # Small table; plain index creation per the 020/023 precedent.
      add_index :attendance_id # rubocop:disable Sequel/ConcurrentIndex
      # Successor of unique(chore_id, user_id, date), which stays until
      # user_id is dropped in the final phase.
      add_index %i[chore_id attendance_id date], # rubocop:disable Sequel/ConcurrentIndex
                unique: true,
                where: Sequel.lit("attendance_id IS NOT NULL"),
                name: :chore_assignments_chore_attendance_date_unique
    end

    # Backfill 1/2: holders with no attendance row on the assignment's event
    # (pinned rows can outlive membership; rows can predate attendances) get
    # a synthesized pending member row, so every assignment can resolve and
    # attendance_id can eventually go NOT NULL.
    run <<~SQL
      INSERT INTO attendances (id, event_id, user_id, status, created_at, updated_at)
      SELECT gen_random_uuid(), missing.event_id, missing.user_id, 'pending', NOW(), NOW()
      FROM (
        SELECT DISTINCT cr.event_id, ca.user_id
        FROM chore_assignments ca
        JOIN chores c ON c.id = ca.chore_id
        JOIN chore_rosters cr ON cr.id = c.chore_roster_id
        LEFT JOIN attendances a ON a.event_id = cr.event_id AND a.user_id = ca.user_id
        WHERE a.id IS NULL
      ) missing
    SQL

    # Backfill 2/2: point every assignment at its holder's attendance row on
    # the roster's event. The updated_at trigger fires on these updates, so
    # connected clients pick the new field up through the regular sync path.
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
    alter_table(:chore_assignments) do
      drop_column :attendance_id
    end
  end
end
