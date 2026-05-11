# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::OnCreated do
  describe ".call" do
    let(:workspace) { TestFactories.workspace }
    let(:owner) { TestFactories.user }
    let(:debtor) { TestFactories.user }
    let(:creditor) { TestFactories.user }
    let(:event) { Event.find(TestFactories.event(workspace: workspace, user: owner)[:id]) }

    let(:transfers) do
      [{ from_user_id: debtor[:id], to_user_id: creditor[:id], amount: 50.00 }]
    end

    it "notifies both sides of every transfer with role-specific copy" do
      described_class.call(transfers: transfers, event: event, workspace_id: workspace[:id])

      rows = DB[:notifications].where(kind: "settlement_created").all
      recipient_ids = rows.map { |r| r[:user_id] }
      expect(recipient_ids).to contain_exactly(debtor[:id], creditor[:id])

      debtor_title = rows.find { |r| r[:user_id] == debtor[:id] }[:data]["title"]
      creditor_title = rows.find { |r| r[:user_id] == creditor[:id] }[:data]["title"]
      expect(debtor_title).to start_with("You owe ")
      expect(creditor_title).to end_with(" owes you €50.00")
    end

    it "is silent when there are no transfers" do
      described_class.call(transfers: [], event: event, workspace_id: workspace[:id])

      expect(DB[:notifications].count).to eq(0)
    end

    it "skips transfers whose users have vanished" do
      ghost = SecureRandom.uuid
      bad = [{ from_user_id: ghost, to_user_id: creditor[:id], amount: 10 }]

      described_class.call(transfers: bad, event: event, workspace_id: workspace[:id])

      expect(DB[:notifications].count).to eq(0)
    end
  end
end
