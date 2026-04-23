# frozen_string_literal: true

require "spec_helper"

RSpec.describe SettlementSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:pool_object) do
        event = TestFactories.event(workspace: workspace, user: user)
        now = Time.now
        settlement_id = SecureRandom.uuid
        DB[:settlements].insert(id: settlement_id, event_id: event[:id], user_id: user[:id], created_at: now, updated_at: now)
        described_class.serialize_batch([Settlement.find(settlement_id)], pool: nil).first
      end

      it_behaves_like "a pool object with createdAt", "settlement"
    end

    it "batches transferIds across multiple settlements" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      s1_id = SecureRandom.uuid
      DB[:settlements].insert(id: s1_id, event_id: event[:id], user_id: user[:id], created_at: now, updated_at: now)
      s2_id = SecureRandom.uuid
      DB[:settlements].insert(id: s2_id, event_id: event[:id], user_id: user[:id], previous_settlement_id: s1_id, created_at: now, updated_at: now)
      t_id = SecureRandom.uuid
      DB[:settlement_transfers].insert(
        id: t_id, settlement_id: s1_id, from_user_id: user[:id], to_user_id: user[:id],
        amount: 5.0, created_at: now, updated_at: now
      )

      settlements = [Settlement.find(s1_id), Settlement.find(s2_id)]
      result = described_class.serialize_batch(settlements, pool: nil)

      expect(result[0][:objectType]).to eq("settlement")
      expect(result[0][:eventId]).to eq(event[:id].to_s)
      expect(result[0][:transferIds]).to include(t_id.to_s)
      expect(result[1][:transferIds]).to eq([])
    end
  end

  describe ".policy_context_batch" do
    it "returns the event for each settlement" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      settlement_id = SecureRandom.uuid
      DB[:settlements].insert(id: settlement_id, event_id: event_row[:id], user_id: user[:id], created_at: now, updated_at: now)
      settlement = Settlement.find(settlement_id)

      context = described_class.policy_context_batch([settlement])

      expect(context[settlement.id.to_s][:event]).to be_a(Event)
      expect(context[settlement.id.to_s][:event].id.to_s).to eq(event_row[:id].to_s)
    end
  end

  describe "policy context threading" do
    it "feeds SettlementPolicy the event kwarg it reads, avoiding the Event.find fallback" do
      event_row = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      settlement_id = SecureRandom.uuid
      DB[:settlements].insert(id: settlement_id, event_id: event_row[:id], user_id: user[:id], created_at: now, updated_at: now)
      settlement = Settlement.find(settlement_id)
      membership_row = TestFactories.workspace_membership(workspace: workspace, user: user)
      membership = WorkspaceMembership.find(membership_row[:id])

      ctx = described_class.policy_context(settlement)
      allow(Event).to receive(:find).and_call_original

      expect(SettlementPolicy.new(settlement, membership: membership, **ctx).delete).to be_success
      expect(Event).not_to have_received(:find)
    end
  end
end
