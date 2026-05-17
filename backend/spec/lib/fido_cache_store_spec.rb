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

    it "falls back to memory-only mode when the dir is on a read-only filesystem" do
      # Stub rather than chmod: on Linux CI containers running as root, file
      # permissions don't bite — the production scenario is a ReadOnly=true
      # mount, which surfaces as EROFS regardless of uid.
      allow(FileUtils).to receive(:mkdir_p).and_raise(Errno::EROFS)
      store = described_class.new(dir: "/anywhere/fido")

      store.write("alpha", { foo: 1 })
      store.write("beta", "bar")

      expect(store.read("alpha")).to eq({ foo: 1 })
      expect(store.read("beta")).to eq("bar")
      expect(store.read("missing")).to be_nil

      store.delete("alpha")
      expect(store.read("alpha")).to be_nil

      store.clear
      expect(store.read("beta")).to be_nil
    end
  end
end
