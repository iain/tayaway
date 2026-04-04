# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe SettlementPolicy do
  let(:event_owner) { TestFactories.user }
  let(:settlement_creator) { TestFactories.user(email: "creator@example.com") }
  let(:other_user) { TestFactories.user(email: "other@example.com") }
  let(:workspace) { TestFactories.workspace }
  let(:event_row) { TestFactories.event(workspace: workspace, user: event_owner) }

  let(:settlement) do
    id = SecureRandom.uuid
    now = Time.now
    DB[:settlements].insert(id: id, event_id: event_row[:id], user_id: settlement_creator[:id], created_at: now, updated_at: now)
    T.must(Settlement.find(id))
  end

  let(:context) { described_class::Context.new(event_owner_user_id: event_owner[:id].to_s) }

  describe "#abilities" do
    it "allows delete for settlement creator" do
      abilities = described_class.new(settlement: settlement, user_id: settlement_creator[:id].to_s, context: context).abilities
      expect(abilities[:delete]).to be_a(BasePolicy::Allowed)
    end

    it "allows delete for event owner" do
      abilities = described_class.new(settlement: settlement, user_id: event_owner[:id].to_s, context: context).abilities
      expect(abilities[:delete]).to be_a(BasePolicy::Allowed)
    end

    it "denies delete for other users" do
      abilities = described_class.new(settlement: settlement, user_id: other_user[:id].to_s, context: context).abilities
      expect(abilities[:delete]).to be_a(BasePolicy::Denied)
      expect(abilities[:delete].reason).to eq("not_owner")
    end
  end
end
