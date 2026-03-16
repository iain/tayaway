# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mailers::Base do
  describe ".deliver" do
    it "delivers the message" do
      message = Mail.new(to: "test@example.com", from: "noreply@tayaway.com", subject: "Test")
      described_class.deliver(message)

      expect(Mail::TestMailer.deliveries.length).to eq(1)
      expect(Mail::TestMailer.deliveries.first.to).to eq(["test@example.com"])
    end

    it "raises errors so callers can handle delivery failures" do
      message = Mail.new(to: "test@example.com", from: "noreply@tayaway.com", subject: "Test")
      allow(message).to receive(:deliver).and_raise(StandardError, "SMTP connection failed")

      expect { described_class.deliver(message) }.to raise_error(StandardError, "SMTP connection failed")
    end
  end

  describe ".from_address" do
    it "returns the configured SMTP_FROM_EMAIL" do
      expect(described_class.from_address).to eq("noreply@tayaway.com")
    end
  end
end
