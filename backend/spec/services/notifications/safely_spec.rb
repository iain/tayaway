# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Safely do
  describe ".deliver" do
    it "returns whatever the block returns when nothing raises" do
      result = described_class.deliver(context: "Spec") { 42 }

      expect(result).to eq(42)
    end

    context "when the block raises in production" do
      before { stub_const("APP_ENV", "production") }

      it "logs with the context and swallows the error" do
        allow(APP_LOGGER).to receive(:error)

        expect do
          described_class.deliver(context: "Some::Service") { raise "boom" }
        end.not_to raise_error

        expect(APP_LOGGER).to have_received(:error) do |&block|
          expect(block.call).to include("[Some::Service]", "boom")
        end
      end
    end

    context "when the block raises in test" do
      it "re-raises so spec failures aren't masked" do
        expect do
          described_class.deliver(context: "Spec") { raise "boom" }
        end.to raise_error("boom")
      end
    end
  end
end
