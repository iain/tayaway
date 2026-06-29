# frozen_string_literal: true

# Make every timestamp column zone-aware.
#
# Three columns predate the convention and are `timestamp WITHOUT time zone`:
# rate_limits.expires_at, idempotency_keys.created_at, and
# audit_log_entries.created_at. Every other timestamp in the schema is already
# `timestamptz`. With the database layer now UTC end to end (see
# config/database.rb), a naive column is a trap: its value is read back as a
# bare wall-clock with no zone, so the host's zone would silently colour it.
#
# The deployment runs in UTC, so the wall-clock already stored in these columns
# *is* the UTC instant — converting to `timestamptz` is value-preserving. The
# migration session is pinned to UTC (config/database.rb's after_connect), so
# PostgreSQL coerces naive -> timestamptz as "this wall-clock is UTC" and, at
# UTC, does it without rewriting the table or its indexes — safe to run against
# the old code still serving traffic during a deploy.
Sequel.migration do
  up do
    run "SET TIME ZONE 'UTC'" # self-documenting; the pooled connection already is

    alter_table(:rate_limits) { set_column_type :expires_at, :timestamptz }
    alter_table(:idempotency_keys) { set_column_type :created_at, :timestamptz }
    alter_table(:audit_log_entries) { set_column_type :created_at, :timestamptz }
  end

  down do
    run "SET TIME ZONE 'UTC'"

    alter_table(:rate_limits) { set_column_type :expires_at, :timestamp }
    alter_table(:idempotency_keys) { set_column_type :created_at, :timestamp }
    alter_table(:audit_log_entries) { set_column_type :created_at, :timestamp }
  end
end
