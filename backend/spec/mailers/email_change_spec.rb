# frozen_string_literal: true

require "spec_helper"

RSpec.describe Mailers::EmailChange do
  before { Mail::TestMailer.deliveries.clear }

  let(:params) do
    {
      email: "new@example.com",
      verification_link: "https://tayaway.nl/email-change/verify?token=abc123"
    }
  end

  describe ".send_email" do
    it "delivers one email to the new address" do
      described_class.send_email(**params)

      expect(Mail::TestMailer.deliveries.length).to eq(1)
      expect(Mail::TestMailer.deliveries.first.to).to eq(["new@example.com"])
    end

    it "includes the verification link in both parts" do
      described_class.send_email(**params)
      message = Mail::TestMailer.deliveries.first

      expect(message.text_part.body.to_s).to include(params[:verification_link])
      expect(message.html_part.body.to_s).to include(params[:verification_link])
    end

    it "sets a display-name From" do
      described_class.send_email(**params)

      expect(Mail::TestMailer.deliveries.first[:from].formatted).to eq(["Tayaway <noreply@tayaway.com>"])
    end

    context "when an unsubscribe address is configured" do
      before { ENV["SMTP_UNSUBSCRIBE_EMAIL"] = "unsubscribe@tayaway.nl" }
      after { ENV.delete("SMTP_UNSUBSCRIBE_EMAIL") }

      it "still does not set List-Unsubscribe (verification is user-requested)" do
        described_class.send_email(**params)

        expect(Mail::TestMailer.deliveries.first["List-Unsubscribe"]).to be_nil
      end
    end
  end
end
