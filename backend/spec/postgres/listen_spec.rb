# frozen_string_literal: true

require "spec_helper"

RSpec.describe Postgres::Listen do
  describe ".subscribe" do
    it "registers LISTEN before the block and UNLISTENs * on normal exit" do
      raw = instance_double(PG::Connection)
      allow(raw).to receive(:query)
      allow(DB).to receive(:synchronize).and_yield(raw)

      described_class.subscribe("some_channel") { |_| :ok }

      expect(raw).to have_received(:query).with("LISTEN some_channel").ordered
      expect(raw).to have_received(:query).with("UNLISTEN *").ordered
    end

    it "still UNLISTENs * when the block raises, then propagates the original error" do
      raw = instance_double(PG::Connection)
      allow(raw).to receive(:query)
      allow(DB).to receive(:synchronize).and_yield(raw)

      expect do
        described_class.subscribe("some_channel") { |_| raise "boom" }
      end.to raise_error(StandardError, "boom")

      expect(raw).to have_received(:query).with("UNLISTEN *")
    end

    it "swallows a failing UNLISTEN so the caller's rescue sees the original cause" do
      # Simulates a dropped connection: wait_for_notify raises, then the
      # UNLISTEN attempted in `ensure` fails too. The helper must not let
      # the secondary error mask the first.
      raw = instance_double(PG::Connection)
      allow(raw).to receive(:query).with("LISTEN some_channel")
      allow(raw).to receive(:query).with("UNLISTEN *").and_raise(StandardError, "connection dead")
      allow(DB).to receive(:synchronize).and_yield(raw)

      expect do
        described_class.subscribe("some_channel") { |_| raise "wait_for_notify failed" }
      end.to raise_error(StandardError, "wait_for_notify failed")
    end

    it "yields the raw connection so callers can park however they like" do
      raw = instance_double(PG::Connection)
      allow(raw).to receive(:query)
      allow(DB).to receive(:synchronize).and_yield(raw)
      yielded = nil

      described_class.subscribe("some_channel") { |conn| yielded = conn }

      expect(yielded).to be(raw)
    end
  end
end
