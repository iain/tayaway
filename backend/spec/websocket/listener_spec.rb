# frozen_string_literal: true

require "spec_helper"

RSpec.describe Websocket::Listener do
  # Reset class-level state between examples so tests are isolated.
  after do
    described_class.instance_variable_set(:@_running_flag, nil)
    described_class.instance_variable_set(:@listen_db, nil)
    described_class.instance_variable_set(:@thread, nil)
  end

  describe ".running?" do
    it "returns false before start is called" do
      expect(described_class.running?).to be(false)
    end

    it "returns true after start is called" do
      allow(Thread).to receive(:new).and_return(double(abort_on_exception: true, "abort_on_exception=": true))
      allow(APP_LOGGER).to receive(:info)

      described_class.start

      expect(described_class.running?).to be(true)
    end
  end

  describe ".start" do
    it "is idempotent — calling twice does not spawn a second thread" do
      thread_double = double(abort_on_exception: true, "abort_on_exception=": true)
      allow(Thread).to receive(:new).once.and_return(thread_double)
      allow(APP_LOGGER).to receive(:info)

      described_class.start
      described_class.start

      expect(Thread).to have_received(:new).once
    end
  end

  describe ".stop" do
    it "is a no-op when not running" do
      allow(APP_LOGGER).to receive(:info)

      expect { described_class.stop }.not_to raise_error
      expect(described_class.running?).to be(false)
    end

    it "sets running? to false after stopping" do
      thread_double = double("abort_on_exception=": true)
      allow(thread_double).to receive(:join)
      allow(Thread).to receive(:new).and_return(thread_double)
      allow(APP_LOGGER).to receive(:info)

      described_class.start
      described_class.stop

      expect(described_class.running?).to be(false)
    end
  end

  describe "thread-safety of the running flag" do
    it "uses a Concurrent::AtomicBoolean for the running flag" do
      flag = described_class.send(:running_flag)

      expect(flag).to be_a(Concurrent::AtomicBoolean)
    end

    it "reflects make_true atomically" do
      flag = described_class.send(:running_flag)
      flag.make_true

      expect(described_class.running?).to be(true)
    end

    it "reflects make_false atomically" do
      flag = described_class.send(:running_flag)
      flag.make_true
      flag.make_false

      expect(described_class.running?).to be(false)
    end
  end
end
