# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::PaymentDetails do
  let(:workspace) { TestFactories.workspace }
  let(:sender) { TestFactories.user(name: "Sender") }
  let(:recipient) { TestFactories.user(name: "Recipient") }
  let(:event) { TestFactories.event(workspace: workspace, user: sender, name: "Trip") }

  let(:sender_membership_row) { TestFactories.workspace_membership(workspace: workspace, user: sender) }
  let(:sender_membership) { WorkspaceMembership.find(sender_membership_row[:id]) }
  let(:recipient_membership_row) { TestFactories.workspace_membership(workspace: workspace, user: recipient) }
  let(:recipient_membership) { WorkspaceMembership.find(recipient_membership_row[:id]) }

  before do
    sender_membership
    recipient_membership
    DB[:users].where(id: recipient[:id]).update(iban: Encryption.encrypt("NL91ABNA0417164300", user_id: recipient[:id]))
  end

  define_method(:create_transfer) do |from_user: sender, to_user: recipient|
    settlement_id = SecureRandom.uuid
    now = Time.now
    DB[:settlements].insert(
      id: settlement_id,
      event_id: event[:id],
      user_id: sender[:id],
      created_at: now,
      updated_at: now
    )
    transfer_id = SecureRandom.uuid
    DB[:settlement_transfers].insert(
      id: transfer_id,
      settlement_id: settlement_id,
      from_user_id: from_user[:id],
      to_user_id: to_user[:id],
      amount: 25.50,
      created_at: now,
      updated_at: now
    )
    transfer_id
  end

  it "returns recipient name, formatted IBAN, amount, and reference for the sender" do
    transfer_id = create_transfer

    result = described_class.call(transfer_id: transfer_id, membership: sender_membership)

    expect(result.success?).to be true
    expect(result.value!).to eq(
      recipientName: "Recipient",
      iban: "NL91 ABNA 0417 1643 00",
      amount: 25.50,
      reference: "Trip"
    )
  end

  it "denies access to the recipient" do
    transfer_id = create_transfer

    result = described_class.call(transfer_id: transfer_id, membership: recipient_membership)

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
  end

  it "denies access to other workspace members" do
    other_user = TestFactories.user(name: "Other")
    other_membership_row = TestFactories.workspace_membership(workspace: workspace, user: other_user)
    other_membership = WorkspaceMembership.find(other_membership_row[:id])
    transfer_id = create_transfer

    result = described_class.call(transfer_id: transfer_id, membership: other_membership)

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
  end

  it "fails when recipient has no IBAN" do
    DB[:users].where(id: recipient[:id]).update(iban: nil)
    transfer_id = create_transfer

    result = described_class.call(transfer_id: transfer_id, membership: sender_membership)

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Recipient has no IBAN configured")
  end

  it "denies access once the transfer is marked paid" do
    transfer_id = create_transfer
    DB[:settlement_transfers].where(id: transfer_id).update(paid_at: Time.now)

    result = described_class.call(transfer_id: transfer_id, membership: sender_membership)

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
  end
end
