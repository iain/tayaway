# typed: false
# frozen_string_literal: true

require "spec_helper"
require "rate_limiter"

RSpec.describe RateLimiter::PgStore do
  let(:store) { described_class.new }

  before do
    DB[:rate_limits].delete
  end

  describe "#increment" do
    it "returns 1 on first call" do
      expect(store.increment("test:key", 1, expires_in: 60)).to eq(1)
    end

    it "increments on subsequent calls" do
      store.increment("test:key", 1, expires_in: 60)
      expect(store.increment("test:key", 1, expires_in: 60)).to eq(2)
    end

    it "resets after expiry" do
      # Insert with an already-expired timestamp
      DB[:rate_limits].insert(key: "test:expired", count: 5, expires_at: Time.now - 1)
      expect(store.increment("test:expired", 1, expires_in: 60)).to eq(1)
    end
  end

  describe "#read" do
    it "returns nil for missing key" do
      expect(store.read("missing")).to be_nil
    end

    it "returns the count for an existing key" do
      store.increment("test:key", 1, expires_in: 60)
      expect(store.read("test:key")).to eq(1)
    end

    it "returns nil after expiry" do
      DB[:rate_limits].insert(key: "test:expired", count: 5, expires_at: Time.now - 1)
      expect(store.read("test:expired")).to be_nil
    end
  end

  describe "#write" do
    it "stores a value" do
      store.write("test:key", 5, expires_in: 60)
      expect(store.read("test:key")).to eq(5)
    end
  end

  describe "#delete" do
    it "removes a key" do
      store.increment("test:key", 1, expires_in: 60)
      store.delete("test:key")
      expect(store.read("test:key")).to be_nil
    end
  end
end
