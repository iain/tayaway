# frozen_string_literal: true

# Replaces the "park scheduled_at 100 years in the future" dead-letter
# trick with an explicit dead_at column. Operational triage queries
# (`SELECT … WHERE dead_at IS NOT NULL`) read more honestly than
# decoding a sentinel timestamp, and the runnable partial index can
# exclude dead rows entirely.
Sequel.migration do
  up do
    alter_table(:async_jobs) do
      add_column :dead_at, DateTime
    end

    run "DROP INDEX async_jobs_runnable"
    run <<~SQL
      CREATE INDEX async_jobs_runnable
      ON async_jobs (scheduled_at)
      WHERE locked_at IS NULL AND dead_at IS NULL
    SQL
  end

  down do
    run "DROP INDEX async_jobs_runnable"
    run <<~SQL
      CREATE INDEX async_jobs_runnable
      ON async_jobs (scheduled_at)
      WHERE locked_at IS NULL
    SQL

    alter_table(:async_jobs) do
      drop_column :dead_at
    end
  end
end
