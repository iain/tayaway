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
      before do
        stub_const("APP_ENV", "production")
        allow(described_class).to receive(:apply_smtp_settings)
      end

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

  describe ".configure!" do
    context "when in production with missing SMTP credentials" do
      let(:saved_env) { ENV.to_h }

      before do
        saved_env # evaluate before deleting
        stub_const("APP_ENV", "production")
        %w[SMTP_HOST SMTP_USERNAME SMTP_PASSWORD].each { |k| ENV.delete(k) }
      end

      after do
        saved_env.each { |k, v| ENV[k] = v }
        # Restore test delivery method after stubbing production
        Mail.defaults { self.delivery_method :test }
      end

      it "does not raise at boot even when SMTP credentials are absent" do
        expect { described_class.configure! }.not_to raise_error
      end
    end
  end

  describe ".from_address" do
    it "returns the configured SMTP_FROM_EMAIL" do
      expect(described_class.from_address).to eq("noreply@tayaway.com")
    end
  end
end
