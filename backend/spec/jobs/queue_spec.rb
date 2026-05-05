# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jobs::Queue do
  before { DB[described_class::TABLE].delete }

  describe ".enqueue" do
    it "runs the job inline in the test environment" do
      stub_const("APP_ENV", "test")
      called_with = nil
      stub_const("Jobs::FakeNoop", Class.new(Jobs::Base) do
        define_method(:call) { |label:| called_with = label }
      end
      )

      described_class.enqueue(job_class: "Jobs::FakeNoop", args: { label: "ran" })

      expect(called_with).to eq("ran")
    end

    it "passes string-keyed args to .run inline so the test path mirrors the JSONB round-trip" do
      # Production path: Postgres returns JSONB with string keys, so .run
      # gets a string-keyed hash. The test path stringifies before calling
      # .run for parity, so a job whose .run depends on string keys behaves
      # the same in both environments.
      stub_const("APP_ENV", "test")
      stub_const("Jobs::FakeKeyCheck", Class.new(Jobs::Base) do
        define_method(:call) { |label:| label }
      end
      )
      allow(Jobs::FakeKeyCheck).to receive(:run).and_call_original

      described_class.enqueue(job_class: "Jobs::FakeKeyCheck", args: { label: "ok" })

      expect(Jobs::FakeKeyCheck).to have_received(:run).with({ "label" => "ok" })
    end

    it "inserts a runnable row outside test mode and the worker can pick it up" do
      stub_const("APP_ENV", "development")
      stub_const("QueueSpecBuffer", [])
      stub_const("Jobs::QueueSpecJob", Class.new(Jobs::Base) do
        define_method(:call) { |value:| QueueSpecBuffer << value }
      end
      )

      described_class.enqueue(job_class: "Jobs::QueueSpecJob", args: { value: "queued" })

      row = DB[described_class::TABLE].first
      expect(row[:job_class]).to eq("Jobs::QueueSpecJob")
      expect(row[:locked_at]).to be_nil
      expect(row[:dead_at]).to be_nil

      # Hand the row to the worker as if it had been NOTIFY-woken — this
      # rounds out the enqueue → claim → run path that would otherwise
      # never be exercised in CI.
      Jobs::Worker.drain

      expect(QueueSpecBuffer).to eq(["queued"])
      expect(DB[described_class::TABLE].count).to eq(0)
    end
  end
end
