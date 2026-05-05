# frozen_string_literal: true

# A durable queue for slow IO that we don't want to do on the request fiber.
# Jobs are claimed via SELECT … FOR UPDATE SKIP LOCKED, so a future jobs
# service running across multiple processes can dequeue safely without
# coordination. The worker wakes from its LISTEN park as soon as enqueue
# fires NOTIFY on the same channel.
#
# `dead_at` (instead of the "park scheduled_at 100 years in the future"
# dead-letter trick) makes operational triage straightforward —
# `SELECT … WHERE dead_at IS NOT NULL` reads more honestly than decoding
# a sentinel timestamp, and the runnable partial index excludes dead rows
# entirely so a stuck job can't keep showing up in claim queries.
Sequel.migration do
  up do
    extension :pg_array

    create_table(:async_jobs) do
      uuid :id, primary_key: true, default: Sequel.function(:gen_random_uuid)
      String :job_class, null: false, text: true
      jsonb :args, null: false, default: "{}"
      DateTime :scheduled_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      Integer :attempts, null: false, default: 0
      DateTime :locked_at
      DateTime :dead_at
      String :last_error, text: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end

    # Partial index over the runnable subset only — locked, future-scheduled,
    # and dead rows stay out of the way of the claim query's
    # ORDER BY scheduled_at LIMIT 1.
    run <<~SQL
      CREATE INDEX async_jobs_runnable
      ON async_jobs (scheduled_at)
      WHERE locked_at IS NULL AND dead_at IS NULL
    SQL
  end

  down do
    drop_table(:async_jobs)
  end
end
