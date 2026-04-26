# frozen_string_literal: true

require "spec_helper"
require "base64"

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

  define_method(:create_transfer) do |from_user: sender, to_user: recipient, event_row: event|
    settlement_id = SecureRandom.uuid
    now = Time.now
    DB[:settlements].insert(
      id: settlement_id,
      event_id: event_row[:id],
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

  it "returns recipient name, formatted IBAN, amount, reference, and a base64 PNG for the sender" do
    transfer_id = create_transfer

    result = described_class.call(transfer_id: transfer_id, membership: sender_membership)

    expect(result.success?).to be true
    value = result.value!
    expect(value[:recipientName]).to eq("Recipient")
    expect(value[:iban]).to eq("NL91 ABNA 0417 1643 00")
    expect(value[:amount]).to eq(25.50)
    expect(value[:reference]).to eq("Trip")

    decoded = Base64.strict_decode64(value[:qrPng])
    expect(decoded.bytes[0..7]).to eq([137, 80, 78, 71, 13, 10, 26, 10])
  end

  it "returns name/amount/reference but null iban and qrPng when the recipient has no IBAN" do
    DB[:users].where(id: recipient[:id]).update(iban: nil)
    transfer_id = create_transfer

    result = described_class.call(transfer_id: transfer_id, membership: sender_membership)

    expect(result.success?).to be true
    value = result.value!
    expect(value[:recipientName]).to eq("Recipient")
    expect(value[:amount]).to eq(25.50)
    expect(value[:reference]).to eq("Trip")
    expect(value[:iban]).to be_nil
    expect(value[:qrPng]).to be_nil
  end

  it "returns the IBAN but no QR when the EPC payload exceeds the 331-byte limit" do
    # The description gets truncated to 140 chars, but each emoji here is
    # 4 bytes — 140 chars × 4 = 560 bytes, well past the 331-byte cap.
    long_event = TestFactories.event(workspace: workspace, user: sender, name: "🎉" * 200)
    transfer_id = create_transfer(event_row: long_event)

    result = described_class.call(transfer_id: transfer_id, membership: sender_membership)

    expect(result.success?).to be true
    value = result.value!
    expect(value[:iban]).to eq("NL91 ABNA 0417 1643 00")
    expect(value[:qrPng]).to be_nil
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

  it "denies access once the transfer is marked paid" do
    transfer_id = create_transfer
    DB[:settlement_transfers].where(id: transfer_id).update(paid_at: Time.now)

    result = described_class.call(transfer_id: transfer_id, membership: sender_membership)

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
  end

  it "returns 404 for a missing transfer" do
    result = described_class.call(
      transfer_id: "00000000-0000-0000-0000-000000000000",
      membership: sender_membership
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
  end

  describe "IBAN formatting" do
    [
      # NL: 18 chars → four groups of 4 + a 2-char tail
      ["NL91ABNA0417164300", "NL91 ABNA 0417 1643 00"],
      # DE: 22 chars → divisible by 4 + 2 → five groups of 4 + a 2-char tail
      ["DE89370400440532013000", "DE89 3704 0044 0532 0130 00"],
      # FR: 27 chars → six groups of 4 + a 3-char tail, includes a letter
      ["FR1420041010050500013M02606", "FR14 2004 1010 0505 0001 3M02 606"],
      # BE: 16 chars → exactly four groups of 4
      ["BE71096123456769", "BE71 0961 2345 6769"],
      # Lower-cased input gets upcased
      ["nl91abna0417164300", "NL91 ABNA 0417 1643 00"],
      # Existing whitespace gets stripped before re-grouping
      ["NL91 ABNA 0417 1643 00", "NL91 ABNA 0417 1643 00"]
    ].each do |raw, formatted|
      it "formats #{raw.inspect} as #{formatted.inspect}" do
        DB[:users].where(id: recipient[:id]).update(iban: Encryption.encrypt(raw, user_id: recipient[:id]))
        transfer_id = create_transfer

        result = described_class.call(transfer_id: transfer_id, membership: sender_membership)

        expect(result.success?).to be true
        expect(result.value!.fetch(:iban)).to eq(formatted)
      end
    end
  end
end
