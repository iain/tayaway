# frozen_string_literal: true

require "spec_helper"

RSpec.describe Jobs::Queue do
  before { DB[described_class::TABLE].delete }

  describe ".enqueue" do
    it "runs the job inline in the test environment" do
      stub_const("APP_ENV", "test")
      called_with = nil
      stub_const("Jobs::FakeNoop", Class.new(Jobs::Base) do
        define_method(:initialize) { |label:| @label = label }
        define_method(:call) { called_with = @label }
      end
      )

      described_class.enqueue(job_class: "Jobs::FakeNoop", args: { label: "ran" })

      expect(called_with).to eq("ran")
    end

    it "stringifies keyword keys before passing them through inline" do
      stub_const("APP_ENV", "test")
      stub_const("Jobs::FakeKeyCheck", Class.new(Jobs::Base) do
        define_method(:initialize) { |label:| @label = label }
        define_method(:call) { @label }
      end
      )

      expect do
        described_class.enqueue(job_class: "Jobs::FakeKeyCheck", args: { label: "ok" })
      end.not_to raise_error
    end

    it "inserts a runnable row outside test mode and the worker can pick it up" do
      stub_const("APP_ENV", "development")
      stub_const("QueueSpecBuffer", [])
      stub_const("Jobs::QueueSpecJob", Class.new(Jobs::Base) do
        define_method(:initialize) { |value:| @value = value }
        define_method(:call) { QueueSpecBuffer << @value }
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
