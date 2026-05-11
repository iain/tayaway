# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::OnPaid do
  describe ".call" do
    let(:workspace) { TestFactories.workspace }
    let(:actor) { TestFactories.user }
    let(:counterparty) { TestFactories.user }

    it "notifies the counterparty with the paid action and amount" do
      described_class.call(
        workspace_id: workspace[:id],
        actor_user_id: actor[:id],
        counterparty_user_id: counterparty[:id],
        amount: 25.50,
        actor_role: "debtor"
      )

      row = DB[:notifications].where(user_id: counterparty[:id], kind: "payment_status_changed").first
      expect(row).not_to be_nil
      expect(row[:data]["title"]).to include("€25.50")
    end

    it "doesn't notify the actor" do
      described_class.call(
        workspace_id: workspace[:id],
        actor_user_id: actor[:id],
        counterparty_user_id: counterparty[:id],
        amount: 25.50,
        actor_role: "debtor"
      )

      expect(DB[:notifications].where(user_id: actor[:id]).count).to eq(0)
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
