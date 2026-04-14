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
end
