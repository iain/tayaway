# frozen_string_literal: true

require "async"

module Jobs
  # Dequeue side of the job system. Runs as a fiber on the worker's reactor
  # next to the WebSocket Listener. Each tick:
  #
  #   1. Claim the next runnable job inside a transaction with
  #      `FOR UPDATE SKIP LOCKED`. Two workers (or future replicas) never
  #      end up holding the same row.
  #   2. Run it. On success, delete the row.
  #   3. On failure, bump `attempts`, schedule a retry with exponential
  #      backoff, or — past the retry budget — leave the row pinned with
  #      `last_error` for human follow-up.
  #
  # Between claims, park on `LISTEN tayaway_jobs` with a poll timeout so a
  # job whose `scheduled_at` is in the future (a delayed retry) gets picked
  # up even if no NOTIFY arrives between now and then.
  module Worker
    MAX_ATTEMPTS = 5
    POLL_INTERVAL = 30 # seconds — bound on how late a delayed job can run

    class << self
      def run
        APP_LOGGER.info { "[Jobs::Worker] Started" }
        loop do
          drain
          wait_for_signal
        end
      end

      # Pull and execute jobs until the runnable queue is empty.
      # Exposed for tests so they can step through one cycle deterministically.
      def drain
        while (row = claim_next)
          execute(row)
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
            .where(locked_at: nil)
            .where { scheduled_at <= Sequel.function(:clock_timestamp) }
            .order(:scheduled_at)
            .for_update
            .skip_locked
            .first
          return nil unless row

          DB[Queue::TABLE].where(id: row[:id]).update(locked_at: Sequel.function(:clock_timestamp))
          row
        end
      end

      def execute(row)
        klass = Object.const_get(row[:job_class])
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
          # Park the row in the dead-letter state: locked_at unset so the
          # claim query skips it (scheduled_at far in the future), and the
          # error record preserved for inspection.
          DB[Queue::TABLE].where(id: row[:id]).update(
            attempts: attempts,
            last_error: message,
            locked_at: nil,
            scheduled_at: Time.now + (365 * 24 * 60 * 60 * 100) # ~100 years
          )
        else
          DB[Queue::TABLE].where(id: row[:id]).update(
            attempts: attempts,
            last_error: message,
            locked_at: nil,
            scheduled_at: Time.now + (2**attempts) # 2s, 4s, 8s, 16s
          )
        end
      end

      def wait_for_signal
        DB.synchronize do |raw|
          raw.query("LISTEN #{Queue::CHANNEL}")
          raw.wait_for_notify(POLL_INTERVAL)
        ensure
          raw.query("UNLISTEN *")
        end
      end
    end
  end
end
