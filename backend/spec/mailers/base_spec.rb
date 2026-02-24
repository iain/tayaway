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

    it "logs and swallows errors instead of raising" do
      message = Mail.new(to: "test@example.com", from: "noreply@tayaway.com", subject: "Test")
      allow(message).to receive(:deliver).and_raise(StandardError, "SMTP connection failed")
      allow(APP_LOGGER).to receive(:error)

      expect { described_class.deliver(message) }.not_to raise_error

      expect(APP_LOGGER).to have_received(:error)
    end
  end

  describe ".from_address" do
    it "returns the configured SMTP_FROM_EMAIL" do
      expect(described_class.from_address).to eq("noreply@tayaway.com")
    end
  end
end
