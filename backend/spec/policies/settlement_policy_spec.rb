# frozen_string_literal: true

require "spec_helper"

RSpec.describe SettlementPolicy do
  let(:workspace) { TestFactories.workspace }
  let(:event_owner) { TestFactories.user }
  let(:settlement_creator) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:event_owner_membership) { TestFactories.workspace_membership(workspace: workspace, user: event_owner) }
  let(:creator_membership) { TestFactories.workspace_membership(workspace: workspace, user: settlement_creator) }
  let(:other_membership) { TestFactories.workspace_membership(workspace: workspace, user: other_user) }
  let(:event_row) { TestFactories.event(workspace: workspace, user: event_owner) }
  let(:event) { Event.find(event_row[:id]) }

  def create_settlement(user:)
    now = Time.now
    id = SecureRandom.uuid
    DB[:settlements].insert(id: id, event_id: event_row[:id], user_id: user[:id], created_at: now, updated_at: now)
    Settlement.find(id)
  end

  describe "#delete" do
    it "allows the settlement creator" do
      settlement = create_settlement(user: settlement_creator)
      policy = described_class.new(settlement, membership: WorkspaceMembership.find(creator_membership[:id]), event: event)
      expect(policy.delete).to be_success
    end

    it "allows the event owner" do
      settlement = create_settlement(user: settlement_creator)
      policy = described_class.new(settlement, membership: WorkspaceMembership.find(event_owner_membership[:id]), event: event)
      expect(policy.delete).to be_success
    end

    it "rejects other users" do
      settlement = create_settlement(user: settlement_creator)
      policy = described_class.new(settlement, membership: WorkspaceMembership.find(other_membership[:id]), event: event)
      expect(policy.delete).to be_failure
      expect(policy.delete.failure).to eq(:not_creator_or_event_owner)
    end

    it "fetches event when not provided" do
      settlement = create_settlement(user: settlement_creator)
      policy = described_class.new(settlement, membership: WorkspaceMembership.find(creator_membership[:id]))
      expect(policy.delete).to be_success
    end
  end
end
