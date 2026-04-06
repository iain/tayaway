# frozen_string_literal: true

require "spec_helper"

RSpec.describe Websocket::Keepalive do
  after do
    described_class.stop if described_class.running?
  end

  describe ".start and .stop" do
    it "starts and reports running?" do
      described_class.start
      expect(described_class.running?).to be true
    end

    it "stops and reports not running?" do
      described_class.start
      described_class.stop
      expect(described_class.running?).to be false
    end

    it "is idempotent — calling start twice does not create two threads" do
      described_class.start
      thread_before = described_class.instance_variable_get(:@thread)
      described_class.start
      thread_after = described_class.instance_variable_get(:@thread)

      expect(thread_after).to eq(thread_before)
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
