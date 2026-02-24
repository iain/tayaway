# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mailers::MagicLink do
  before { Mail::TestMailer.deliveries.clear }

  describe ".send_email" do
    let(:email) { "user@example.com" }
    let(:magic_link) { "https://tayaway.com/auth/verify?token=abc123" }

    before { described_class.send_email(email: email, magic_link: magic_link) }

    it "delivers one email" do
      expect(Mail::TestMailer.deliveries.length).to eq(1)
    end

    it "sends to the correct recipient" do
      expect(Mail::TestMailer.deliveries.first.to).to eq([email])
    end

    it "sends from the configured address" do
      expect(Mail::TestMailer.deliveries.first.from).to eq(["noreply@tayaway.com"])
    end

    it "has the correct subject" do
      expect(Mail::TestMailer.deliveries.first.subject).to eq("Sign in to Tayaway")
    end

    it "includes the magic link in the text part" do
      message = Mail::TestMailer.deliveries.first
      text_body = message.text_part.body.to_s

      expect(text_body).to include(magic_link)
    end

    it "includes the magic link in the HTML part" do
      message = Mail::TestMailer.deliveries.first
      html_body = message.html_part.body.to_s

      expect(html_body).to include(magic_link)
    end

    it "has both text and HTML parts" do
      message = Mail::TestMailer.deliveries.first

      expect(message.text_part).not_to be_nil
      expect(message.html_part).not_to be_nil
    end
  end
end
