# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::GenerateQr do
  let(:workspace) { TestFactories.workspace }
  let(:sender) { TestFactories.user(name: "Sender") }
  let(:recipient) { TestFactories.user(name: "Recipient") }
  let(:event) { TestFactories.event(workspace: workspace, user: sender, name: "Trip") }

  before do
    TestFactories.workspace_membership(workspace: workspace, user: sender)
    TestFactories.workspace_membership(workspace: workspace, user: recipient)
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
      current_user_id: sender[:id]
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
      current_user_id: recipient[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("Only the sender can request the QR code")
  end

  it "returns 400 when recipient has no IBAN" do
    DB[:users].where(id: recipient[:id]).update(iban: nil)
    transfer_id = create_transfer

    result = described_class.call(
      transfer_id: transfer_id,
      current_user_id: sender[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Recipient has no IBAN configured")
  end

  it "returns 403 when sender is not a workspace member" do
    # Create a user who is the from_user but not in the workspace
    outsider = TestFactories.user(name: "Outsider")
    transfer_id = create_transfer(from_user: outsider)

    result = described_class.call(
      transfer_id: transfer_id,
      current_user_id: outsider[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("Access denied")
  end

  it "returns 404 for missing transfer" do
    result = described_class.call(
      transfer_id: "00000000-0000-0000-0000-000000000000",
      current_user_id: sender[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
  end
end
