# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mailers::Base do
  describe ".deliver" do
    it "delivers the message" do
      message = Mail.new(to: "test@example.com", from: "noreply@tayaway.nl", subject: "Test")
      described_class.deliver(message)

      expect(Mail::TestMailer.deliveries.length).to eq(1)
      expect(Mail::TestMailer.deliveries.first.to).to eq(["test@example.com"])
    end

    it "raises errors so callers can handle delivery failures" do
      message = Mail.new(to: "test@example.com", from: "noreply@tayaway.nl", subject: "Test")
      allow(message).to receive(:deliver).and_raise(StandardError, "SMTP connection failed")

      expect { described_class.deliver(message) }.to raise_error(StandardError, "SMTP connection failed")
    end
  end

  describe ".configure!" do
    context "when in production with SMTP feature disabled" do
      it "does not raise at boot" do
        stub_const("APP_ENV", "production")
        expect { described_class.configure! }.not_to raise_error
      ensure
        Mail.defaults { self.delivery_method :test }
      end
    end
  end

  describe ".from_address" do
    it "returns the configured SMTP from address" do
      expect(described_class.from_address).to eq("noreply@tayaway.nl")
    end
  end

  describe ".from_header" do
    it "wraps the from address with the default display name" do
      expect(described_class.from_header).to eq("Tayaway <noreply@tayaway.nl>")
    end

    it "honours smtp_from_name when set" do
      Config.with(smtp_from_name: "Tayaway Events") do
        expect(described_class.from_header).to eq("Tayaway Events <noreply@tayaway.nl>")
      end
    end
  end

  describe ".reply_to_address" do
    it "is nil when reply-to is unset" do
      Config.with(smtp_reply_to_email: nil) do
        expect(described_class.reply_to_address).to be_nil
      end
    end

    it "returns the configured reply-to" do
      Config.with(smtp_reply_to_email: "support@tayaway.nl") do
        expect(described_class.reply_to_address).to eq("support@tayaway.nl")
      end
    end
  end

  describe ".unsubscribe_mailto" do
    it "is nil when the unsubscribe address is unset" do
      Config.with(smtp_unsubscribe_email: nil) do
        expect(described_class.unsubscribe_mailto).to be_nil
      end
    end

    it "wraps the address in angle brackets with an unsubscribe subject" do
      Config.with(smtp_unsubscribe_email: "unsubscribe@tayaway.nl") do
        expect(described_class.unsubscribe_mailto).to eq("<mailto:unsubscribe@tayaway.nl?subject=unsubscribe>")
      end
    end
  end

  describe ".apply_sender_headers" do
    let(:message) { Mail.new(to: "user@example.com", subject: "Test") }

    it "sets From with the display name" do
      described_class.apply_sender_headers(message)
      expect(message[:from].formatted).to eq(["Tayaway <noreply@tayaway.nl>"])
    end

    it "sets Reply-To when configured" do
      Config.with(smtp_reply_to_email: "support@tayaway.nl") do
        described_class.apply_sender_headers(message)
        expect(message.reply_to).to eq(["support@tayaway.nl"])
      end
    end

    it "omits Reply-To when unset" do
      Config.with(smtp_reply_to_email: nil) do
        described_class.apply_sender_headers(message)
        expect(message.reply_to).to be_nil
      end
    end

    it "sets List-Unsubscribe when unsubscribable and an address is configured" do
      Config.with(smtp_unsubscribe_email: "unsubscribe@tayaway.nl") do
        described_class.apply_sender_headers(message, unsubscribable: true)
        expect(message["List-Unsubscribe"].to_s).to eq("<mailto:unsubscribe@tayaway.nl?subject=unsubscribe>")
      end
    end

    it "does not set List-Unsubscribe when not unsubscribable, even if configured" do
      Config.with(smtp_unsubscribe_email: "unsubscribe@tayaway.nl") do
        described_class.apply_sender_headers(message, unsubscribable: false)
        expect(message["List-Unsubscribe"]).to be_nil
      end
    end

    it "does not set List-Unsubscribe when unsubscribable but no address is configured" do
      Config.with(smtp_unsubscribe_email: nil) do
        described_class.apply_sender_headers(message, unsubscribable: true)
        expect(message["List-Unsubscribe"]).to be_nil
      end
    end
  end
end
