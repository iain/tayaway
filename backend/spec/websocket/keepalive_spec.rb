# frozen_string_literal: true

require "spec_helper"

RSpec.describe Websocket::Keepalive do
  describe "constants" do
    it "has a 30 second ping interval" do
      expect(described_class::PING_INTERVAL).to eq(30)
    end

    it "has a 90 second idle timeout" do
      expect(described_class::IDLE_TIMEOUT).to eq(90)
    end
  end

  describe ".tick" do
    let(:manager) { instance_double(Websocket::ConnectionManager) }

    it "asks the connection manager to ping all and prune at the configured idle timeout" do
      allow(manager).to receive(:ping_all).and_return(0)

      described_class.tick(manager)

      expect(manager).to have_received(:ping_all).with(idle_timeout: described_class::IDLE_TIMEOUT)
    end

    it "swallows errors from the connection manager so the run loop keeps going" do
      allow(manager).to receive(:ping_all).and_raise(StandardError, "boom")
      allow(APP_LOGGER).to receive(:error)

      expect { described_class.tick(manager) }.not_to raise_error
      expect(APP_LOGGER).to have_received(:error)
    end
  end
end
