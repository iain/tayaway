# frozen_string_literal: true

require "async"

module Jobs
  # Dequeue side of the job system. Runs as a fiber on the worker's reactor
  # next to the WebSocket Listener. Each tick:
  #
  #   1. Sweep stuck claims — rows whose previous worker died (SIGKILL,
  #      OOM, ungraceful container restart) holding `locked_at`. SKIP
  #      LOCKED + the RECLAIM_AFTER threshold ensures we never steal a
  #      row from a still-running peer.
  #   2. Claim the next runnable job inside a transaction with
  #      `FOR UPDATE SKIP LOCKED`. Two workers (or future replicas) never
  #      end up holding the same row.
  #   3. Run it. On success, delete the row.
  #   4. On failure, bump `attempts`, schedule a retry with exponential
  #      backoff, or — past the retry budget — set `dead_at` and leave
  #      the row in place with `last_error` for human follow-up.
  #
  # The whole loop runs inside one `LISTEN tayaway_jobs` parked on a
  # single pooled connection. Holding the LISTEN across drains (rather
  # than re-subscribing each cycle) closes the gap where a NOTIFY could
  # land between `UNLISTEN` and the next subscribe and be dropped.
  module Worker
    MAX_ATTEMPTS = 5
    POLL_INTERVAL = 30 # seconds — bound on how late a delayed job can run
    # On a transient loop-level error we lose at most this many seconds of
    # NOTIFY signal — claim_next still finds runnable jobs on the next
    # iteration regardless, so this only affects how soon we retry the
    # connection itself.
    RETRY_DELAY = 1
    # Comfortably above database.rb's 30s statement_timeout, so an
    # actually-running job is never mistaken for an orphaned one.
    RECLAIM_AFTER = 300

    class << self
      def run
        APP_LOGGER.info { "[Jobs::Worker] Started" }
        Postgres::Listen.subscribe(Queue::CHANNEL) do |raw|
          loop do
            reclaim_stale
            drain
            raw.wait_for_notify(POLL_INTERVAL)
          rescue StandardError => e
            # Transient errors at the loop level — typically a dropped DB
            # connection during claim_next or wait_for_notify. Sleep and
            # retry instead of letting the fiber die and waiting for the
            # container to restart us.
            APP_LOGGER.error do
              "[Jobs::Worker] Loop error: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
            end
            Async::Task.current.sleep(RETRY_DELAY)
          end
        end
      end

      # Pull and execute jobs until the runnable queue is empty.
      # Exposed for tests so they can step through one cycle deterministically.
      def drain
        while (row = claim_next)
          execute(row)
        end
      end

      # Recover jobs whose previous worker died holding `locked_at` (SIGKILL,
      # OOM, ungraceful container restart). Routed through `handle_failure`
      # so a job that consistently kills its worker still hits the retry
      # budget and ends up dead instead of cycling forever. The whole row
      # selection + bookkeeping happens inside one transaction so the
      # FOR UPDATE lock prevents a peer worker from picking up the row
      # between us seeing it and us clearing `locked_at`.
      def reclaim_stale
        loop do
          handled = DB.transaction do
            row = DB[Queue::TABLE]
                  .where(dead_at: nil)
                  .exclude(locked_at: nil)
                  .where { locked_at <= Sequel.function(:clock_timestamp) - Sequel.cast("#{RECLAIM_AFTER} seconds", :interval) }
                  .order(:locked_at)
                  .for_update
                  .skip_locked
                  .first
            next false unless row

            handle_failure(row, RuntimeError.new("Worker died holding lock for >#{RECLAIM_AFTER}s"))
            true
          end
          break unless handled
        end
      end

      private

      def claim_next
        DB.transaction do
          # clock_timestamp() (rather than CURRENT_TIMESTAMP / now()) returns
          # actual wall time. CURRENT_TIMESTAMP returns the *outer*
          # transaction's start, which under nested savepoints (and in test
          # examples wrapped by database_cleaner) is older than the
          # scheduled_at of rows inserted inside that same transaction.
          row = DB[Queue::TABLE]
                .where(locked_at: nil, dead_at: nil)
                .where { scheduled_at <= Sequel.function(:clock_timestamp) }
                .order(:scheduled_at)
                .for_update
                .skip_locked
                .first
          if row
            DB[Queue::TABLE].where(id: row[:id]).update(locked_at: Sequel.function(:clock_timestamp))
            row
          end
        end
      end

      def execute(row)
        klass = Object.const_get(row[:job_class])
        # Defense in depth: the queue is internal, but if anything ever
        # writes a non-Jobs class name into the table the claim → run
        # path would otherwise call `.run` on whatever class it resolves
        # to. Restrict to known job subclasses.
        unless klass.is_a?(Class) && klass < Jobs::Base
          raise "Refusing to run #{row[:job_class]} — not a Jobs::Base subclass"
        end

        klass.run(row[:args])
        DB[Queue::TABLE].where(id: row[:id]).delete
      rescue StandardError => e
        handle_failure(row, e)
      end

      def handle_failure(row, error)
        attempts = row[:attempts] + 1
        message = "#{error.class}: #{error.message}"
        APP_LOGGER.error do
          "[Jobs::Worker] #{row[:job_class]} #{row[:id]} failed (attempt #{attempts}): #{message}"
        end

        if attempts >= MAX_ATTEMPTS
          DB[Queue::TABLE].where(id: row[:id]).update(
            attempts: attempts,
            last_error: message,
            locked_at: nil,
            dead_at: Sequel.function(:clock_timestamp)
          )
        else
          # Anchor the next-run time to the DB clock so scheduled_at uses
          # the same source as claim_next's `scheduled_at <= clock_timestamp()`
          # comparison; mixing Time.now in here would drift on any clock skew
          # between app server and DB.
          backoff_seconds = 2**attempts # 2s, 4s, 8s, 16s
          DB[Queue::TABLE].where(id: row[:id]).update(
            attempts: attempts,
            last_error: message,
            locked_at: nil,
            scheduled_at: Sequel.function(:clock_timestamp) +
              Sequel.cast("#{backoff_seconds} seconds", :interval)
          )
        end
      end
    end
  end
end
