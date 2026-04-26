# frozen_string_literal: true

require "spec_helper"

RSpec.describe RequestContext do
  after { described_class.reset! }

  it "exposes named accessors and nests scopes" do
    expect(described_class.request_id).to be_nil

    described_class.with(request_id: "outer") do
      expect(described_class.request_id).to eq("outer")

      described_class.with(idempotency_key_hash: "h") do
        expect(described_class.request_id).to eq("outer")
        expect(described_class.idempotency_key_hash).to eq("h")
      end

      # Inner scope's keys are gone, outer keys preserved.
      expect(described_class.request_id).to eq("outer")
      expect(described_class.idempotency_key_hash).to be_nil
    end

    expect(described_class.request_id).to be_nil
  end

  it "rejects unknown keys at call time so typos fail loud" do
    expect {
      described_class.with(request_idd: "typo") { :unused }
    }.to raise_error(ArgumentError, /Unknown.*request_idd/)
  end

  it "doesn't leak between sibling scopes" do
    described_class.with(request_id: "first") { :noop }
    expect(described_class.request_id).to be_nil

    described_class.with(request_id: "second") do
      expect(described_class.request_id).to eq("second")
    end
    expect(described_class.request_id).to be_nil
  end

  it "restores the previous context when the block raises" do
    expect {
      described_class.with(request_id: "transient") { raise "boom" }
    }.to raise_error("boom")
    expect(described_class.request_id).to be_nil
  end

  it "propagates context to child fibers but doesn't let them clobber the parent" do
    described_class.with(request_id: "parent") do
      child_view = Fiber.new { described_class.request_id }.resume
      expect(child_view).to eq("parent")

      Fiber.new do
        described_class.with(request_id: "child") do
          # child fiber sees its own scope
        end
      end.resume

      # Parent unaffected.
      expect(described_class.request_id).to eq("parent")
    end
  end
end
