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

  describe ".deliver_later" do
    before { Mail::TestMailer.deliveries.clear }

    context "when not in production" do
      it "delivers the message synchronously" do
        message = Mail.new(to: "test@example.com", from: "noreply@tayaway.com", subject: "Test")
        described_class.deliver_later(message)

        expect(Mail::TestMailer.deliveries.length).to eq(1)
        expect(Mail::TestMailer.deliveries.first.to).to eq(["test@example.com"])
      end

      it "raises errors so callers can detect delivery failures" do
        message = Mail.new(to: "test@example.com", from: "noreply@tayaway.com", subject: "Test")
        allow(message).to receive(:deliver).and_raise(StandardError, "SMTP connection failed")

        expect { described_class.deliver_later(message) }.to raise_error(StandardError, "SMTP connection failed")
      end
    end

    context "when in production" do
      before { stub_const("APP_ENV", "production") }

      it "delivers the message in a background thread" do
        message = Mail.new(to: "test@example.com", from: "noreply@tayaway.com", subject: "Test")
        described_class.deliver_later(message)

        sleep 0.1
        expect(Mail::TestMailer.deliveries.length).to eq(1)
      end

      it "logs delivery failures without re-raising" do
        message = Mail.new(to: "fail@example.com", from: "noreply@tayaway.com", subject: "Test")
        allow(message).to receive(:deliver).and_raise(StandardError, "SMTP unreachable")

        logged_errors = []
        allow(APP_LOGGER).to receive(:error) do |&block|
          logged_errors << block.call
        end

        expect { described_class.deliver_later(message) }.not_to raise_error

        sleep 0.1
        expect(Mail::TestMailer.deliveries).to be_empty
        expect(logged_errors).to include(a_string_matching(/SMTP unreachable/))
      end
    end
  end

  describe ".from_address" do
    it "returns the configured SMTP_FROM_EMAIL" do
      expect(described_class.from_address).to eq("noreply@tayaway.com")
    end
  end
end
