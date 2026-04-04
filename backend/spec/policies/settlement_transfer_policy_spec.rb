# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SettlementTransferPolicy do
  let(:recipient) { TestFactories.user }
  let(:sender) { TestFactories.user(email: "sender@example.com") }
  let(:other_user) { TestFactories.user(email: "other@example.com") }
  let(:workspace) { TestFactories.workspace }
  let(:event_row) { TestFactories.event(workspace: workspace, user: recipient) }

  let(:settlement_id) do
    id = SecureRandom.uuid
    now = Time.now
    DB[:settlements].insert(id: id, event_id: event_row[:id], user_id: recipient[:id], created_at: now, updated_at: now)
    id
  end

  let(:transfer) do
    id = SecureRandom.uuid
    now = Time.now
    DB[:settlement_transfers].insert(
      id: id, settlement_id: settlement_id,
      from_user_id: sender[:id], to_user_id: recipient[:id],
      amount: 25.0, created_at: now, updated_at: now
    )
    T.must(SettlementTransfer.find(id))
  end

  describe "#abilities" do
    it "allows mark_paid for the recipient" do
      abilities = described_class.new(transfer: transfer, user_id: recipient[:id].to_s).abilities
      expect(abilities[:mark_paid]).to be_a(BasePolicy::Allowed)
    end

    it "denies mark_paid for the sender" do
      abilities = described_class.new(transfer: transfer, user_id: sender[:id].to_s).abilities
      expect(abilities[:mark_paid]).to be_a(BasePolicy::Denied)
      expect(abilities[:mark_paid].reason).to eq("not_recipient")
    end

    it "denies mark_paid for other users" do
      abilities = described_class.new(transfer: transfer, user_id: other_user[:id].to_s).abilities
      expect(abilities[:mark_paid]).to be_a(BasePolicy::Denied)
    end
  end
end
