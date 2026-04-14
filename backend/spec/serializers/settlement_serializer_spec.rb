# frozen_string_literal: true

require "spec_helper"

RSpec.describe SettlementSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    it "batches transferIds across multiple settlements" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      s1_id = SecureRandom.uuid
      DB[:settlements].insert(id: s1_id, event_id: event[:id], user_id: user[:id], created_at: now, updated_at: now)
      s2_id = SecureRandom.uuid
      DB[:settlements].insert(id: s2_id, event_id: event[:id], user_id: user[:id], created_at: now, updated_at: now)
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
end
