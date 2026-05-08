# frozen_string_literal: true

require "spec_helper"

RSpec.describe Notifications::Kinds::SettlementOwesYou do
  let(:params) do
    {
      email: "alice@example.com",
      recipient_name: "Alice",
      debtor_name: "Iain",
      amount: 12.5,
      event_name: "Trip",
      event_url: "https://tayaway.nl/events/abc"
    }
  end

  describe ".build_email" do
    it "addresses the creditor" do
      message = described_class.build_email(**params)

      expect(message.to).to eq(["alice@example.com"])
    end

    it "names the debtor and amount in the subject" do
      message = described_class.build_email(**params)

      expect(message.subject).to eq("Iain owes you €12.50 for Trip")
    end
  end

  describe ".in_app_payload" do
    it "renders a recipient-facing title and body" do
      payload = described_class.in_app_payload(**params)

      expect(payload[:title]).to eq("Iain owes you €12.50")
      expect(payload[:body]).to eq("for Trip")
    end
  end
end
