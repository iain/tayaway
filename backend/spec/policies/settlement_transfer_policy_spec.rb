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

  def create_transfer(from_user:, to_user:, superseded: false, paid: false)
    event_row = TestFactories.event(workspace: workspace, user: from_user)
    now = Time.now
    settlement_id = SecureRandom.uuid
    DB[:settlements].insert(id: settlement_id, event_id: event_row[:id], user_id: from_user[:id], created_at: now, updated_at: now)
    transfer_id = SecureRandom.uuid
    DB[:settlement_transfers].insert(
      id: transfer_id, settlement_id: settlement_id,
      from_user_id: from_user[:id], to_user_id: to_user[:id],
      amount: 50.0,
      superseded_at: superseded ? now : nil,
      paid_at: paid ? now : nil,
      created_at: now, updated_at: now
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

    it "rejects even the recipient when the transfer is superseded" do
      transfer = create_transfer(from_user: sender, to_user: recipient, superseded: true)
      policy = described_class.new(transfer, membership: WorkspaceMembership.find(recipient_membership[:id]))
      expect(policy.mark_paid).to be_failure
      expect(policy.mark_paid.failure).to eq(:superseded)
    end

    it "rejects even the recipient when a follow-up settlement has locked the chain" do
      transfer = create_transfer(from_user: sender, to_user: recipient, paid: true)
      policy = described_class.new(
        transfer,
        membership: WorkspaceMembership.find(recipient_membership[:id]),
        has_successor: true
      )
      expect(policy.mark_paid).to be_failure
      expect(policy.mark_paid.failure).to eq(:locked_in_followup)
    end

    it "still allows mark_paid when has_successor flag is set but the transfer is unpaid" do
      # Unpaid + successor shouldn't actually arise in production (Create
      # supersedes any unpaid transfers when issuing a follow-up), but the
      # policy stays narrow: only paid+successor is the locked-in case.
      transfer = create_transfer(from_user: sender, to_user: recipient, paid: false)
      policy = described_class.new(
        transfer,
        membership: WorkspaceMembership.find(recipient_membership[:id]),
        has_successor: true
      )
      expect(policy.mark_paid).to be_success
    end
  end

  describe "#generate_qr" do
    it "allows the sender" do
      transfer = create_transfer(from_user: sender, to_user: recipient)
      policy = described_class.new(transfer, membership: WorkspaceMembership.find(sender_membership[:id]))
      expect(policy.generate_qr).to be_success
    end

    it "rejects the recipient" do
      transfer = create_transfer(from_user: sender, to_user: recipient)
      policy = described_class.new(transfer, membership: WorkspaceMembership.find(recipient_membership[:id]))
      expect(policy.generate_qr).to be_failure
      expect(policy.generate_qr.failure).to eq(:not_sender)
    end

    it "rejects other users" do
      transfer = create_transfer(from_user: sender, to_user: recipient)
      policy = described_class.new(transfer, membership: WorkspaceMembership.find(other_membership[:id]))
      expect(policy.generate_qr).to be_failure
      expect(policy.generate_qr.failure).to eq(:not_sender)
    end

    it "rejects even the sender when the transfer is superseded" do
      transfer = create_transfer(from_user: sender, to_user: recipient, superseded: true)
      policy = described_class.new(transfer, membership: WorkspaceMembership.find(sender_membership[:id]))
      expect(policy.generate_qr).to be_failure
      expect(policy.generate_qr.failure).to eq(:superseded)
    end

    it "rejects QR for a transfer that's already paid" do
      transfer = create_transfer(from_user: sender, to_user: recipient, paid: true)
      policy = described_class.new(transfer, membership: WorkspaceMembership.find(sender_membership[:id]))
      expect(policy.generate_qr).to be_failure
      expect(policy.generate_qr.failure).to eq(:already_paid)
    end
  end
end
