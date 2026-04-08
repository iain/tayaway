# frozen_string_literal: true

require "spec_helper"

RSpec.describe SettlementTransferPolicy do
  let(:workspace) { TestFactories.workspace }
  let(:recipient) { TestFactories.user }
  let(:sender) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:recipient_membership) { TestFactories.workspace_membership(workspace: workspace, user: recipient) }
  let(:sender_membership) { TestFactories.workspace_membership(workspace: workspace, user: sender) }
  let(:other_membership) { TestFactories.workspace_membership(workspace: workspace, user: other_user) }

  def create_transfer(from_user:, to_user:)
    event_row = TestFactories.event(workspace: workspace, user: from_user)
    now = Time.now
    settlement_id = SecureRandom.uuid
    DB[:settlements].insert(id: settlement_id, event_id: event_row[:id], user_id: from_user[:id], created_at: now, updated_at: now)
    transfer_id = SecureRandom.uuid
    DB[:settlement_transfers].insert(
      id: transfer_id, settlement_id: settlement_id,
      from_user_id: from_user[:id], to_user_id: to_user[:id],
      amount: 50.0, created_at: now, updated_at: now
    )
    SettlementTransfer.find(transfer_id)
  end

  describe "#mark_paid" do
    it "allows the transfer recipient" do
      transfer = create_transfer(from_user: sender, to_user: recipient)
      policy = described_class.new(transfer, membership: WorkspaceMembership.find(recipient_membership[:id]))
      expect(policy.mark_paid).to be_success
    end

    it "rejects the sender" do
      transfer = create_transfer(from_user: sender, to_user: recipient)
      policy = described_class.new(transfer, membership: WorkspaceMembership.find(sender_membership[:id]))
      expect(policy.mark_paid).to be_failure
      expect(policy.mark_paid.failure).to eq(:not_recipient)
    end

    it "rejects other users" do
      transfer = create_transfer(from_user: sender, to_user: recipient)
      policy = described_class.new(transfer, membership: WorkspaceMembership.find(other_membership[:id]))
      expect(policy.mark_paid).to be_failure
    end
  end
end
