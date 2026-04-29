# frozen_string_literal: true

require "spec_helper"
require "base64"

RSpec.describe Settlements::NetPaymentDetails do
  let(:workspace) { TestFactories.workspace }
  let(:alice) { TestFactories.user(name: "Alice") }
  let(:bob)   { TestFactories.user(name: "Bob") }
  let(:alice_membership) do
    row = TestFactories.workspace_membership(workspace: workspace, user: alice)
    WorkspaceMembership.find(row[:id])
  end
  let(:bob_membership) do
    row = TestFactories.workspace_membership(workspace: workspace, user: bob)
    WorkspaceMembership.find(row[:id])
  end

  before do
    alice_membership
    bob_membership
    DB[:users].where(id: bob[:id]).update(
      iban: Encryption.encrypt("NL91ABNA0417164300", user_id: bob[:id])
    )
  end

  def create_transfer(event:, from:, to:, amount:)
    settlement_id = SecureRandom.uuid
    now = Time.now
    DB[:settlements].insert(
      id: settlement_id,
      event_id: event[:id],
      user_id: from[:id],
      created_at: now,
      updated_at: now
    )
    transfer_id = SecureRandom.uuid
    DB[:settlement_transfers].insert(
      id: transfer_id,
      settlement_id: settlement_id,
      from_user_id: from[:id],
      to_user_id: to[:id],
      amount: amount,
      created_at: now,
      updated_at: now
    )
    transfer_id
  end

  it "returns recipient name, formatted IBAN, the net amount, and a QR for the net sender" do
    event1 = TestFactories.event(workspace: workspace, user: alice, name: "Trip A")
    event2 = TestFactories.event(workspace: workspace, user: alice, name: "Trip B")
    create_transfer(event: event1, from: alice, to: bob, amount: 50.0)
    create_transfer(event: event2, from: bob, to: alice, amount: 10.0)

    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: bob[:id],
      expected_amount: 40.0,
      membership: alice_membership
    )

    expect(result.success?).to be true
    value = result.value!
    expect(value[:recipientName]).to eq("Bob")
    expect(value[:iban]).to eq("NL91 ABNA 0417 1643 00")
    expect(value[:amount]).to eq(40.0)
    expect(value[:reference]).to eq("Trip A, Trip B")
    expect(Base64.strict_decode64(value[:qrPng]).bytes[0..7]).to eq([137, 80, 78, 71, 13, 10, 26, 10])
  end

  it "rejects when the caller is the net recipient instead of the sender" do
    event = TestFactories.event(workspace: workspace, user: alice)
    create_transfer(event: event, from: alice, to: bob, amount: 50.0)

    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: alice[:id],
      expected_amount: 50.0,
      membership: bob_membership
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("not_sender")
  end

  it "rejects when the expected amount no longer matches the live net" do
    event = TestFactories.event(workspace: workspace, user: alice)
    create_transfer(event: event, from: alice, to: bob, amount: 50.0)

    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: bob[:id],
      expected_amount: 40.0,
      membership: alice_membership
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(409)
  end

  it "falls back to a workspace-name reference when joined event names overflow" do
    long_workspace = TestFactories.workspace(name: "Long Workspace")
    long_alice_membership_row = TestFactories.workspace_membership(workspace: long_workspace, user: alice)
    long_alice_membership = WorkspaceMembership.find(long_alice_membership_row[:id])
    TestFactories.workspace_membership(workspace: long_workspace, user: bob)

    # 5 × 30-byte names plus separators ≈ 162 bytes — past the 140 limit.
    5.times do |i|
      event = TestFactories.event(workspace: long_workspace, user: alice, name: "Long Event Name Number #{i.to_s.rjust(5, "0")}")
      create_transfer(event: event, from: alice, to: bob, amount: 10.0)
    end

    result = described_class.call(
      workspace_id: long_workspace[:id],
      counterparty_user_id: bob[:id],
      expected_amount: 50.0,
      membership: long_alice_membership
    )

    expect(result.success?).to be true
    expect(result.value![:reference]).to eq("Long Workspace settlement")
  end

  it "validates required inputs" do
    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: nil,
      expected_amount: 1.0,
      membership: alice_membership
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(400)
  end
end
