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
  def initialize(label:)
    super()
    @label = label
  end

  def call
    WorkerSpecRecorder.behaviour.call(@label)
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
      expect(row[:last_error]).to include("boom")
      expect(row[:scheduled_at]).to be > Time.now
    end

    it "parks rows past the retry budget into the dead-letter horizon" do
      WorkerSpecRecorder.behaviour = ->(_) { raise "boom" }
      allow(APP_LOGGER).to receive(:error)
      insert_job(args: { label: "dead" }, attempts: described_class::MAX_ATTEMPTS - 1)

      described_class.drain

      row = DB[Jobs::Queue::TABLE].first
      expect(row[:attempts]).to eq(described_class::MAX_ATTEMPTS)
      expect(row[:scheduled_at]).to be > Time.now + (50 * 365 * 24 * 60 * 60)
    end
  end
end
