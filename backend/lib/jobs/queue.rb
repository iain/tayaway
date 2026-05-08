# frozen_string_literal: true

module Jobs
  # Enqueue side of the job system. Inserts a row into `async_jobs` and
  # NOTIFYs the worker channel so any parked Jobs::Worker fiber wakes up
  # immediately. In the test environment, jobs run inline so specs don't
  # need a worker loop or to clean up the table after each example.
  module Queue
    CHANNEL = "tayaway_jobs"
    TABLE = :async_jobs

    class << self
      # @param job_class [String] fully-qualified class name of a Jobs::Base subclass
      # @param args [Hash] keyword arguments to persist with the job
      # @param scheduled_at [Time, nil] earliest time the job may run; defaults to now
      def enqueue(job_class:, args:, scheduled_at: nil)
        if APP_ENV == "test"
          # Run synchronously so specs can assert on side-effects without
          # spinning up a worker. The inline path can't honour
          # `scheduled_at`, so refuse it loudly rather than diverging
          # from production semantics — exercise delayed jobs by
          # inserting directly and calling Worker.drain.
          if scheduled_at
            raise ArgumentError, "Jobs::Queue.enqueue with `scheduled_at` is not supported in test mode"
          end

          Object.const_get(job_class).run(args.transform_keys(&:to_s))
          return
        end

        DB[TABLE].insert(
          job_class: job_class,
          args: Sequel.pg_jsonb(args),
          scheduled_at: scheduled_at || Sequel::CURRENT_TIMESTAMP
        )
        DB.notify(CHANNEL)
      end
    end
  end
end
