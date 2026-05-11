# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::OnUnpaid do
  describe ".call" do
    let(:workspace) { TestFactories.workspace }
    let(:actor) { TestFactories.user }
    let(:counterparty) { TestFactories.user }

    it "notifies the counterparty with the unpaid action" do
      described_class.call(
        workspace_id: workspace[:id],
        actor_user_id: actor[:id],
        counterparty_user_id: counterparty[:id],
        amount: 25.50,
        actor_role: "creditor"
      )

      row = DB[:notifications].where(user_id: counterparty[:id], kind: "payment_status_changed").first
      expect(row).not_to be_nil
      expect(row[:data]["title"]).to match(/reverted|unmarked/i)
    end

    it "is silent when the counterparty has vanished" do
      described_class.call(
        workspace_id: workspace[:id],
        actor_user_id: actor[:id],
        counterparty_user_id: SecureRandom.uuid,
        amount: 25.50,
        actor_role: "debtor"
      )

      expect(DB[:notifications].count).to eq(0)
    end
  end
end
