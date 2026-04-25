# frozen_string_literal: true

require "spec_helper"

RSpec.describe SettlementTransferSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:other_user) { TestFactories.user }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:pool_object) do
        event = TestFactories.event(workspace: workspace, user: user)
        now = Time.now
        settlement_id = SecureRandom.uuid
        DB[:settlements].insert(id: settlement_id, event_id: event[:id], user_id: user[:id], created_at: now, updated_at: now)
        transfer_id = SecureRandom.uuid
        DB[:settlement_transfers].insert(
          id: transfer_id, settlement_id: settlement_id,
          from_user_id: other_user[:id], to_user_id: user[:id], amount: 1.0,
          created_at: now, updated_at: now
        )
        described_class.serialize_batch([SettlementTransfer.find(transfer_id)], pool: nil).first
      end

      it_behaves_like "a pool object with createdAt", "settlementTransfer"
    end

    it "serializes transfer fields" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      settlement_id = SecureRandom.uuid
      DB[:settlements].insert(
        id: settlement_id, event_id: event[:id], user_id: user[:id],
        created_at: now, updated_at: now
      )
      transfer_id = SecureRandom.uuid
      DB[:settlement_transfers].insert(
        id: transfer_id, settlement_id: settlement_id,
        from_user_id: other_user[:id], to_user_id: user[:id], amount: 10.5,
        created_at: now, updated_at: now
      )
      transfer = SettlementTransfer.find(transfer_id)

      result = described_class.serialize_batch([transfer], pool: nil).first

      expect(result[:id]).to eq(transfer.id.to_s)
      expect(result[:objectType]).to eq("settlementTransfer")
      expect(result[:settlementId]).to eq(settlement_id.to_s)
      expect(result[:fromUserId]).to eq(other_user[:id].to_s)
      expect(result[:toUserId]).to eq(user[:id].to_s)
      expect(result[:amount]).to eq(10.5)
      expect(result[:paidAt]).to be_nil
    end
  end

  describe ".policy_context_batch" do
    it "flags transfers whose settlement has a successor in the chain" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      s1_id = SecureRandom.uuid
      s2_id = SecureRandom.uuid
      DB[:settlements].insert(id: s1_id, event_id: event[:id], user_id: user[:id], created_at: now, updated_at: now)
      DB[:settlements].insert(
        id: s2_id, event_id: event[:id], user_id: user[:id],
        previous_settlement_id: s1_id, created_at: now, updated_at: now
      )
      t1_id = SecureRandom.uuid
      t2_id = SecureRandom.uuid
      DB[:settlement_transfers].insert(
        id: t1_id, settlement_id: s1_id,
        from_user_id: other_user[:id], to_user_id: user[:id], amount: 1.0,
        created_at: now, updated_at: now
      )
      DB[:settlement_transfers].insert(
        id: t2_id, settlement_id: s2_id,
        from_user_id: other_user[:id], to_user_id: user[:id], amount: 1.0,
        created_at: now, updated_at: now
      )
      transfers = [SettlementTransfer.find(t1_id), SettlementTransfer.find(t2_id)]

      context = described_class.policy_context_batch(transfers)

      expect(context[t1_id.to_s][:has_successor]).to be true
      expect(context[t2_id.to_s][:has_successor]).to be false
    end
  end
end
