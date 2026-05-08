# frozen_string_literal: true

require "spec_helper"

# Class-level state on a real top-level class so it survives Class.new
# without tripping Ruby 4's ban on class-variable access from anonymous
# classes. The worker spec swaps `behaviour` per example to choose between
# happy-path and raising flows.
module WorkerSpecRecorder
  class << self
    attr_accessor :results, :behaviour

    def reset!
      @results = []
      @behaviour = ->(label) { @results << label }
    end
  end
end
WorkerSpecRecorder.reset!

class WorkerSpecJob < Jobs::Base
  def call(label:)
    WorkerSpecRecorder.behaviour.call(label)
  end
end

RSpec.describe Jobs::Worker do
  before do
    DB[Jobs::Queue::TABLE].delete
    WorkerSpecRecorder.reset!
  end

  describe ".drain" do
    def insert_job(args:, scheduled_at: Time.now, attempts: 0, locked_at: nil)
      DB[Jobs::Queue::TABLE].insert(
        job_class: "WorkerSpecJob",
        args: Sequel.pg_jsonb(args),
        scheduled_at: scheduled_at,
        attempts: attempts,
        locked_at: locked_at
      )
    end

    it "runs and deletes a runnable job" do
      insert_job(args: { label: "first" })

      described_class.drain

      expect(WorkerSpecRecorder.results).to eq(["first"])
      expect(DB[Jobs::Queue::TABLE].count).to eq(0)
    end

    it "drains multiple runnable jobs in scheduled-order" do
      insert_job(args: { label: "older" }, scheduled_at: Time.now - 10)
      insert_job(args: { label: "newer" }, scheduled_at: Time.now - 1)

      described_class.drain

      expect(WorkerSpecRecorder.results).to eq(%w[older newer])
    end

    it "skips jobs scheduled in the future" do
      insert_job(args: { label: "later" }, scheduled_at: Time.now + 60)
      insert_job(args: { label: "now" })

      described_class.drain

      expect(WorkerSpecRecorder.results).to eq(["now"])
      expect(DB[Jobs::Queue::TABLE].count).to eq(1)
    end

    it "schedules a retry with exponential backoff on failure" do
      WorkerSpecRecorder.behaviour = ->(_) { raise "boom" }
      allow(APP_LOGGER).to receive(:error)
      insert_job(args: { label: "fail" })

      described_class.drain

      row = DB[Jobs::Queue::TABLE].first
      expect(row[:attempts]).to eq(1)
      expect(row[:locked_at]).to be_nil
      expect(row[:dead_at]).to be_nil
      expect(row[:last_error]).to include("boom")
      expect(row[:scheduled_at]).to be > Time.now
    end

    it "applies a 2**attempts backoff so each retry waits longer than the last" do
      WorkerSpecRecorder.behaviour = ->(_) { raise "boom" }
      allow(APP_LOGGER).to receive(:error)
      insert_job(args: { label: "fail" }, attempts: 2)

      before = Time.now
      described_class.drain
      after = Time.now

      row = DB[Jobs::Queue::TABLE].first
      # attempts becomes 3, so backoff is 2**3 = 8 seconds
      expect(row[:scheduled_at]).to be_between(before + 8, after + 8 + 1)
    end

    it "marks rows past the retry budget as dead and stops claiming them" do
      WorkerSpecRecorder.behaviour = ->(_) { raise "boom" }
      allow(APP_LOGGER).to receive(:error)
      insert_job(args: { label: "dead" }, attempts: described_class::MAX_ATTEMPTS - 1)

      described_class.drain

      row = DB[Jobs::Queue::TABLE].first
      expect(row[:attempts]).to eq(described_class::MAX_ATTEMPTS)
      expect(row[:dead_at]).not_to be_nil

      # Even though scheduled_at is in the past, the dead row stays out
      # of the runnable set on the next cycle.
      WorkerSpecRecorder.results.clear
      described_class.drain
      expect(WorkerSpecRecorder.results).to be_empty
    end

    it "ignores rows whose locked_at was set by another worker still in flight" do
      insert_job(args: { label: "claimed" }, locked_at: Time.now - 1)

      described_class.drain

      expect(WorkerSpecRecorder.results).to be_empty
      row = DB[Jobs::Queue::TABLE].first
      expect(row[:locked_at]).not_to be_nil
    end

    it "refuses to run a class that isn't a Jobs::Base subclass" do
      stub_const("WorkerSpecImposter", Class.new do
        def self.run(_); end
      end
      )
      allow(APP_LOGGER).to receive(:error)
      DB[Jobs::Queue::TABLE].insert(
        job_class: "WorkerSpecImposter",
        args: Sequel.pg_jsonb({}),
        scheduled_at: Time.now
      )

      described_class.drain

      row = DB[Jobs::Queue::TABLE].first
      expect(row[:last_error]).to match(/Refusing to run/)
    end
  end

  describe ".reclaim_stale" do
    def insert_locked_job(attempts: 0, locked_at:, dead_at: nil)
      DB[Jobs::Queue::TABLE].insert(
        job_class: "WorkerSpecJob",
        args: Sequel.pg_jsonb({}),
        scheduled_at: Time.now - 60,
        attempts: attempts,
        locked_at: locked_at,
        dead_at: dead_at
      )
    end

    it "reclaims rows whose locked_at is older than RECLAIM_AFTER" do
      allow(APP_LOGGER).to receive(:error)
      insert_locked_job(locked_at: Time.now - described_class::RECLAIM_AFTER - 60)

      described_class.reclaim_stale

      row = DB[Jobs::Queue::TABLE].first
      expect(row[:attempts]).to eq(1)
      expect(row[:locked_at]).to be_nil
      expect(row[:dead_at]).to be_nil
      expect(row[:last_error]).to match(/lock/i)
      expect(row[:scheduled_at]).to be > Time.now
    end

    it "leaves recently-locked rows alone — the worker may still be running them" do
      insert_locked_job(locked_at: Time.now - 5)

      described_class.reclaim_stale

      row = DB[Jobs::Queue::TABLE].first
      expect(row[:locked_at]).not_to be_nil
      expect(row[:attempts]).to eq(0)
    end

    it "marks reclaimed rows as dead once attempts hit the retry budget" do
      allow(APP_LOGGER).to receive(:error)
      insert_locked_job(
        attempts: described_class::MAX_ATTEMPTS - 1,
        locked_at: Time.now - described_class::RECLAIM_AFTER - 1
      )

      described_class.reclaim_stale

      row = DB[Jobs::Queue::TABLE].first
      expect(row[:attempts]).to eq(described_class::MAX_ATTEMPTS)
      expect(row[:dead_at]).not_to be_nil
    end

    it "skips already-dead rows so a stuck dead row isn't re-touched" do
      insert_locked_job(
        attempts: described_class::MAX_ATTEMPTS,
        locked_at: Time.now - described_class::RECLAIM_AFTER - 60,
        dead_at: Time.now - 60
      )

      expect { described_class.reclaim_stale }.not_to(change {
        DB[Jobs::Queue::TABLE].first.values_at(:attempts, :locked_at, :dead_at)
      }
                                                     )
    end

    it "leaves rows with locked_at: nil alone — only stuck claims are its concern" do
      DB[Jobs::Queue::TABLE].insert(
        job_class: "WorkerSpecJob",
        args: Sequel.pg_jsonb({}),
        scheduled_at: Time.now - 60,
        attempts: 0,
        locked_at: nil
      )

      described_class.reclaim_stale

      row = DB[Jobs::Queue::TABLE].first
      expect(row[:attempts]).to eq(0)
      expect(row[:last_error]).to be_nil
    end
  end

  describe ".run" do
    # `.run`'s outer loop is infinite by design. Each example stubs
    # `listen_once` so a few iterations fire and the loop is broken out
    # of via `throw`. `Async::Task.current` is stubbed because no reactor
    # is running in the spec.

    it "logs and recovers from a transient error instead of letting the fiber die" do
      iterations = 0
      allow(described_class).to receive(:listen_once) do
        iterations += 1
        throw :stop_test_loop if iterations >= 2

        raise "transient"
      end
      allow(Async::Task).to receive(:current).and_return(instance_double(Async::Task, sleep: nil))
      allow(APP_LOGGER).to receive(:info)
      logged = []
      allow(APP_LOGGER).to receive(:error) { |&block| logged << block.call }

      catch(:stop_test_loop) { described_class.run }

      expect(iterations).to be >= 2
      expect(logged).to include(a_string_matching(/Loop error.*transient/))
    end

    it "sleeps RETRY_DELAY before retrying so a hot failure can't busy-loop" do
      slept = []
      task = instance_double(Async::Task)
      allow(task).to receive(:sleep) { |seconds| slept << seconds }
      allow(Async::Task).to receive(:current).and_return(task)
      allow(APP_LOGGER).to receive(:info)
      allow(APP_LOGGER).to receive(:error)

      iterations = 0
      allow(described_class).to receive(:listen_once) do
        iterations += 1
        throw :stop_test_loop if iterations >= 2

        raise "still broken"
      end

      catch(:stop_test_loop) { described_class.run }

      expect(slept).to eq([described_class::RETRY_DELAY])
    end

    it "re-enters listen_once after an error so a dead LISTEN connection is replaced" do
      # If the parked connection dies (PG::ConnectionBad from
      # wait_for_notify), the rescue must let the error escape
      # `listen_once` so its DB.listen returns the (likely dead)
      # connection to the pool — Sequel discards it on next checkout —
      # and the next iteration calls listen_once again with a fresh
      # one. Without that, the worker would keep polling on a dead
      # socket until the container restarted.
      calls = 0
      allow(described_class).to receive(:listen_once) do
        calls += 1
        throw :stop_test_loop if calls >= 2

        raise PG::ConnectionBad, "server closed the connection"
      end
      allow(Async::Task).to receive(:current).and_return(instance_double(Async::Task, sleep: nil))
      allow(APP_LOGGER).to receive(:info)
      allow(APP_LOGGER).to receive(:error)

      catch(:stop_test_loop) { described_class.run }

      expect(calls).to be >= 2
    end
  end

  describe ".listen_once" do
    it "drives drain via DB.listen's after_listen + loop callbacks instead of polling raw conn" do
      tick_calls = 0
      allow(described_class).to receive(:reclaim_stale) { tick_calls += 1 }
      allow(described_class).to receive(:drain)
      received_opts = nil
      allow(DB).to receive(:listen) do |channel, opts, &_block|
        received_opts = opts.merge(channel: channel)
        # Simulate Sequel: run after_listen, then run loop callback once
        # to mirror a single wake/timeout cycle, then return.
        opts[:after_listen].call(:fake_conn)
        opts[:loop].call(:fake_conn)
      end

      described_class.send(:listen_once)

      expect(received_opts[:channel]).to eq(Jobs::Queue::CHANNEL)
      expect(received_opts[:timeout]).to eq(described_class::POLL_INTERVAL)
      expect(tick_calls).to eq(2)
    end
  end
end
