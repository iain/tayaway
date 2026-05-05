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
    # The loop is infinite by design; each example stubs the parts that
    # touch the reactor (`Postgres::Listen.subscribe` and the raw
    # connection's `wait_for_notify`) so a few iterations happen and then
    # the loop is broken out of via `throw`. `Async::Task.current` is
    # stubbed out because no reactor is running in the spec.
    def stub_subscribe_yielding(raw)
      allow(Postgres::Listen).to receive(:subscribe).with(Jobs::Queue::CHANNEL).and_yield(raw)
    end

    it "logs and recovers from a transient error instead of letting the fiber die" do
      iterations = 0
      allow(described_class).to receive(:drain) do
        iterations += 1
        raise "transient" if iterations == 1
      end
      raw = instance_double(PG::Connection)
      allow(raw).to receive(:wait_for_notify) do
        throw :stop_test_loop if iterations >= 2
      end
      stub_subscribe_yielding(raw)
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
      allow(described_class).to receive(:drain) do
        iterations += 1
        raise "still broken" if iterations == 1
      end
      raw = instance_double(PG::Connection)
      allow(raw).to receive(:wait_for_notify) do
        throw :stop_test_loop if iterations >= 2
      end
      stub_subscribe_yielding(raw)

      catch(:stop_test_loop) { described_class.run }

      expect(slept).to eq([described_class::RETRY_DELAY])
    end
  end
end
