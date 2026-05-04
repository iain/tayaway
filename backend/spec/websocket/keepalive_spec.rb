# frozen_string_literal: true

require "spec_helper"
require "async"

RSpec.describe Websocket::Keepalive do
  after do
    described_class.instance_variable_set(:@task, nil)
  end

  describe ".running?" do
    it "is false before start" do
      expect(described_class.running?).to be false
    end

    it "is true while a non-finished task is registered" do
      task_double = instance_double(Async::Task, finished?: false)
      described_class.instance_variable_set(:@task, task_double)

      expect(described_class.running?).to be true
    end
  end

  describe ".start" do
    it "raises when called outside an Async reactor" do
      expect { described_class.start }.to raise_error(/Async reactor/)
    end

    it "spawns a task on the current reactor and is idempotent" do
      allow(APP_LOGGER).to receive(:info)
      # Stub the run loop so the spawned task exits immediately rather than
      # ticking on the real interval.
      allow(described_class).to receive(:run_loop)

      Sync do
        described_class.start
        first = described_class.instance_variable_get(:@task)
        described_class.start
        second = described_class.instance_variable_get(:@task)

        expect(first).to be_a(Async::Task)
        expect(second).to equal(first)
      end
    end
  end

  describe ".stop" do
    it "is a no-op when not running" do
      allow(APP_LOGGER).to receive(:info)

      expect { described_class.stop }.not_to raise_error
      expect(described_class.running?).to be false
    end

    it "stops the task and clears state" do
      allow(APP_LOGGER).to receive(:info)
      allow(described_class).to receive(:run_loop)

      Sync do
        described_class.start
        described_class.stop

        expect(described_class.running?).to be false
        expect(described_class.instance_variable_get(:@task)).to be_nil
      end
    end
  end

  describe "constants" do
    it "has a 30 second ping interval" do
      expect(described_class::PING_INTERVAL).to eq(30)
    end

    it "has a 90 second idle timeout" do
      expect(described_class::IDLE_TIMEOUT).to eq(90)
    end
  end
end
