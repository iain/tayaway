# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Kinds::SettlementOwed do
  let(:params) do
    {
      email: "iain@example.com",
      recipient_name: "Iain",
      creditor_name: "Alice",
      amount: 12.5,
      event_name: "Trip",
      event_url: "https://tayaway.nl/events/abc"
    }
  end

  describe ".build_email" do
    it "addresses the debtor" do
      message = described_class.build_email(**params)

      expect(message.to).to eq(["iain@example.com"])
    end

    it "names the creditor and amount in the subject" do
      message = described_class.build_email(**params)

      expect(message.subject).to eq("You owe Alice €12.50 for Trip")
    end

    it "includes the formatted amount in the bodies" do
      message = described_class.build_email(**params)

      expect(message.text_part.body.to_s).to include("€12.50")
      expect(message.html_part.body.to_s).to include("€12.50")
    end
  end

  describe ".in_app_payload" do
    it "renders a recipient-facing title and body" do
      payload = described_class.in_app_payload(**params)

      expect(payload[:title]).to eq("You owe Alice €12.50")
      expect(payload[:body]).to eq("for Trip")
      expect(payload[:href]).to eq("https://tayaway.nl/events/abc")
    end

    it "ignores extra data keys (kind classes get the full data hash)" do
      expect {
        described_class.in_app_payload(**params, email: "x", recipient_name: "y")
      }.not_to raise_error
    end
  end
end
