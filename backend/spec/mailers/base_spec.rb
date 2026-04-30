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

  describe ".from_header" do
    it "wraps the from address with the default display name" do
      expect(described_class.from_header).to eq("Tayaway <noreply@tayaway.com>")
    end

    it "honours SMTP_FROM_NAME when set" do
      ENV["SMTP_FROM_NAME"] = "Tayaway Events"
      expect(described_class.from_header).to eq("Tayaway Events <noreply@tayaway.com>")
    ensure
      ENV.delete("SMTP_FROM_NAME")
    end
  end

  describe ".reply_to_address" do
    it "is nil when SMTP_REPLY_TO_EMAIL is unset" do
      ENV.delete("SMTP_REPLY_TO_EMAIL")
      expect(described_class.reply_to_address).to be_nil
    end

    it "returns the configured SMTP_REPLY_TO_EMAIL" do
      ENV["SMTP_REPLY_TO_EMAIL"] = "support@tayaway.nl"
      expect(described_class.reply_to_address).to eq("support@tayaway.nl")
    ensure
      ENV.delete("SMTP_REPLY_TO_EMAIL")
    end
  end

  describe ".unsubscribe_mailto" do
    it "is nil when SMTP_UNSUBSCRIBE_EMAIL is unset" do
      ENV.delete("SMTP_UNSUBSCRIBE_EMAIL")
      expect(described_class.unsubscribe_mailto).to be_nil
    end

    it "wraps the address in angle brackets with an unsubscribe subject" do
      ENV["SMTP_UNSUBSCRIBE_EMAIL"] = "unsubscribe@tayaway.nl"
      expect(described_class.unsubscribe_mailto).to eq("<mailto:unsubscribe@tayaway.nl?subject=unsubscribe>")
    ensure
      ENV.delete("SMTP_UNSUBSCRIBE_EMAIL")
    end
  end

  describe ".apply_sender_headers" do
    let(:message) { Mail.new(to: "user@example.com", subject: "Test") }

    it "sets From with the display name" do
      described_class.apply_sender_headers(message)
      expect(message[:from].formatted).to eq(["Tayaway <noreply@tayaway.com>"])
    end

    it "sets Reply-To when SMTP_REPLY_TO_EMAIL is configured" do
      ENV["SMTP_REPLY_TO_EMAIL"] = "support@tayaway.nl"
      described_class.apply_sender_headers(message)
      expect(message.reply_to).to eq(["support@tayaway.nl"])
    ensure
      ENV.delete("SMTP_REPLY_TO_EMAIL")
    end

    it "omits Reply-To when SMTP_REPLY_TO_EMAIL is unset" do
      ENV.delete("SMTP_REPLY_TO_EMAIL")
      described_class.apply_sender_headers(message)
      expect(message.reply_to).to be_nil
    end

    it "sets List-Unsubscribe when unsubscribable and SMTP_UNSUBSCRIBE_EMAIL is configured" do
      ENV["SMTP_UNSUBSCRIBE_EMAIL"] = "unsubscribe@tayaway.nl"
      described_class.apply_sender_headers(message, unsubscribable: true)
      expect(message["List-Unsubscribe"].to_s).to eq("<mailto:unsubscribe@tayaway.nl?subject=unsubscribe>")
    ensure
      ENV.delete("SMTP_UNSUBSCRIBE_EMAIL")
    end

    it "does not set List-Unsubscribe when not unsubscribable, even if configured" do
      ENV["SMTP_UNSUBSCRIBE_EMAIL"] = "unsubscribe@tayaway.nl"
      described_class.apply_sender_headers(message, unsubscribable: false)
      expect(message["List-Unsubscribe"]).to be_nil
    ensure
      ENV.delete("SMTP_UNSUBSCRIBE_EMAIL")
    end

    it "does not set List-Unsubscribe when unsubscribable but SMTP_UNSUBSCRIBE_EMAIL is unset" do
      ENV.delete("SMTP_UNSUBSCRIBE_EMAIL")
      described_class.apply_sender_headers(message, unsubscribable: true)
      expect(message["List-Unsubscribe"]).to be_nil
    end
  end
end
