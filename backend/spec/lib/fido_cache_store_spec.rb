# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe FidoCacheStore do
  describe "#initialize" do
    it "creates the cache directory when the parent is writable" do
      Dir.mktmpdir do |tmp|
        dir = File.join(tmp, "fido")
        described_class.new(dir: dir)
        expect(Dir.exist?(dir)).to be true
      end
    end

    it "falls back to memory-only mode when the parent is read-only" do
      Dir.mktmpdir do |tmp|
        File.chmod(0o555, tmp)
        store = described_class.new(dir: File.join(tmp, "fido"))

        store.write("key", "value")
        expect(store.read("key")).to eq("value")
        File.chmod(0o755, tmp)
      end
    end
  end

  describe "round trips through the memory cache when disk is unusable" do
    it "still serves writes via the in-memory hash" do
      Dir.mktmpdir do |tmp|
        File.chmod(0o555, tmp)
        store = described_class.new(dir: File.join(tmp, "fido"))

        store.write("alpha", { foo: 1 })
        store.write("beta", "bar")

        expect(store.read("alpha")).to eq({ foo: 1 })
        expect(store.read("beta")).to eq("bar")
        expect(store.read("missing")).to be_nil

        store.delete("alpha")
        expect(store.read("alpha")).to be_nil

        store.clear
        expect(store.read("beta")).to be_nil
        File.chmod(0o755, tmp)
      end
    end
  end
end
