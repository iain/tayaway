# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::GenerateQr do
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
    DB[:users].where(id: recipient[:id]).update(iban: "NL91ABNA0417164300")
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

  it "returns a PNG blob for a valid transfer" do
    transfer_id = create_transfer

    result = described_class.call(
      transfer_id: transfer_id,
      membership: sender_membership
    )

    expect(result.success?).to be true
    png = result.value!
    # PNG files start with the 8-byte PNG signature
    expect(png.bytes[0..7]).to eq([137, 80, 78, 71, 13, 10, 26, 10])
  end

  it "returns 403 when requested by non-sender" do
    transfer_id = create_transfer

    result = described_class.call(
      transfer_id: transfer_id,
      membership: recipient_membership
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("not_sender")
  end

  it "returns 400 when recipient has no IBAN" do
    DB[:users].where(id: recipient[:id]).update(iban: nil)
    transfer_id = create_transfer

    result = described_class.call(
      transfer_id: transfer_id,
      membership: sender_membership
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Recipient has no IBAN configured")
  end

  it "returns 403 when a different workspace member requests the QR code" do
    # A third workspace member who is neither sender nor recipient
    other_user = TestFactories.user(name: "Other Member")
    other_membership_row = TestFactories.workspace_membership(workspace: workspace, user: other_user)
    other_membership = WorkspaceMembership.find(other_membership_row[:id])
    transfer_id = create_transfer

    result = described_class.call(
      transfer_id: transfer_id,
      membership: other_membership
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("not_sender")
  end

  it "returns 404 for missing transfer" do
    result = described_class.call(
      transfer_id: "00000000-0000-0000-0000-000000000000",
      membership: sender_membership
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
  end
end
