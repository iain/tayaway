# frozen_string_literal: true

module Maintenance
  # Prunes the temporary/auth/sync tables whose rows are only ever consulted
  # while unexpired, so nothing else deletes them and their row counts would
  # otherwise climb forever (see issue #411).
  #
  # `call` does the deletes and is a pure, idempotent sweep — safe to run any
  # number of times. The nested `Job` wraps it as a daily, self-rescheduling
  # background job on the durable async_jobs queue: each run schedules the
  # next, and `ensure_scheduled` (called at jobs-worker startup) seeds the
  # first run and heals the chain if a run ever dies. There is deliberately no
  # rake task or OS cron entry — the server prunes itself.
  #
  # `rate_limits` is intentionally absent: it self-cleans opportunistically on
  # every 100th increment (see RateLimiter::PgStore). `async_jobs` is absent
  # too — the worker deletes each job on success, and the handful of `dead_at`
  # rows that linger are kept on purpose for operational triage.
  module PruneExpired
    JOB_CLASS = "Maintenance::PruneExpired::Job"

    # Daily cadence. The queue polls every 30s, so the actual run drifts a few
    # seconds past this — fine for a maintenance sweep.
    INTERVAL = 24 * 60 * 60

    # Retries beyond this window re-execute rather than replay their cached
    # response; Stripe uses the same 24h horizon. Runtime never expires these
    # rows (`Idempotency.lookup` has no time filter), so this is the only thing
    # that bounds the table.
    IDEMPOTENCY_TTL = 24 * 60 * 60

    class << self
      # Deletes dead rows across the target tables and returns a
      # `{ table => rows_deleted }` hash for the caller to log. Each predicate
      # keys off the same columns runtime checks — `expires_at`, a consumption
      # stamp (`used_at`/`accepted_at`), or an age cutoff. Conservative by
      # construction: it removes only what a column predicate can prove dead,
      # so e.g. a merely-inactive session (a Ruby-side check in Session, not a
      # stored flag) is left for its `expires_at` to catch.
      #
      # Not wrapped in a transaction on purpose: the deletes are independent,
      # and letting each commit on its own avoids one long lock-holding
      # transaction and lets a partial run still make progress before a retry.
      def call(now: Time.now)
        {
          # ws_tickets FK-cascade from sessions, but a ws_ticket (30s TTL)
          # always outlives its session's expiry, so no live ticket ever
          # references a pruned session — order doesn't matter.
          ws_tickets: delete_consumed_or_expired(:ws_tickets, :used_at, now),
          sessions: DB[:sessions].where { expires_at <= now }.delete,
          login_link_tokens: delete_consumed_or_expired(:login_link_tokens, :used_at, now),
          email_change_tokens: delete_consumed_or_expired(:email_change_tokens, :used_at, now),
          workspace_invites: delete_consumed_or_expired(:workspace_invites, :accepted_at, now),
          idempotency_keys: DB[:idempotency_keys].where { created_at < now - IDEMPOTENCY_TTL }.delete,
          # Tombstones only feed partial syncs, which the server caps at
          # RETENTION_PERIOD — a `since` older than that forces a full sync
          # that ignores deleted_items entirely. Tie the window to that
          # constant so this stays correct if the sync horizon ever moves.
          deleted_items: DB[:deleted_items].where { deleted_at < now - Sync::WorkspaceSync::RETENTION_PERIOD }.delete
        }
      end

      # Seeds the recurring schedule when nothing is pending, preserving an
      # existing next-run time so repeated deploys don't keep pushing the run
      # forward. A dead job doesn't count as pending, so a chain broken by a
      # job that exhausted its retries re-seeds here on the next boot.
      def ensure_scheduled(now: Time.now)
        return if DB[Jobs::Queue::TABLE].where(job_class: JOB_CLASS, dead_at: nil).any?

        schedule_at(now)
      end

      # Queues the next daily run, collapsing any stray pending copies into a
      # single row first. The currently-running job holds `locked_at`, so it is
      # never one of the rows deleted here.
      def schedule_next
        DB.transaction do
          DB[Jobs::Queue::TABLE].where(job_class: JOB_CLASS, locked_at: nil, dead_at: nil).delete
          schedule_at(Sequel.function(:clock_timestamp) + Sequel.cast("#{INTERVAL} seconds", :interval))
        end
      end

      private

      def delete_consumed_or_expired(table, consumed_column, now)
        DB[table].where { expires_at <= now }.or(Sequel.~(consumed_column => nil)).delete
      end

      def schedule_at(scheduled_at)
        DB[Jobs::Queue::TABLE].insert(
          job_class: JOB_CLASS,
          args: Sequel.pg_jsonb({}),
          scheduled_at: scheduled_at
        )
        DB.notify(Jobs::Queue::CHANNEL)
      end
    end

    # The persisted daily job. Prunes, then queues tomorrow's run — the reorder
    # only happens after a successful sweep, so a failed run retries (with
    # backoff) without ever double-scheduling.
    class Job < Jobs::Base
      def call
        counts = PruneExpired.call
        APP_LOGGER.info { "[Maintenance::PruneExpired] #{counts.map { |t, n| "#{t}=#{n}" }.join(' ')}" }
        PruneExpired.schedule_next
      end
    end
  end
end
