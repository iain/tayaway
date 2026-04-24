# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::MarkPaid do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }
  let(:recipient) { TestFactories.user }
  let(:event) { TestFactories.event(workspace: workspace, user: user) }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  # -- test helper used across examples
  def create_transfer(paid_at: nil)
    settlement_id = SecureRandom.uuid
    now = Time.now
    DB[:settlements].insert(
      id: settlement_id,
      event_id: event[:id],
      user_id: user[:id],
      created_at: now,
      updated_at: now
    )
    transfer_id = SecureRandom.uuid
    DB[:settlement_transfers].insert(
      id: transfer_id,
      settlement_id: settlement_id,
      from_user_id: user[:id],
      to_user_id: recipient[:id],
      amount: 25.0,
      paid_at: paid_at,
      created_at: now,
      updated_at: now
    )
    transfer_id
  end
  it "returns 404 when transfer not found" do
    result = described_class.call(
      transfer_id: SecureRandom.uuid,
      paid: true,
      membership: membership_for(recipient),
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
  end

  it "marks a transfer as paid" do
    transfer_id = create_transfer

    result = described_class.call(
      transfer_id: transfer_id,
      paid: true,
      membership: membership_for(recipient),
      workspace_id: workspace[:id]
    )

    expect(result.success?).to be true
    obj = result.value![:objects].find { |o| o[:objectType] == "settlementTransfer" }
    expect(obj[:paidAt]).not_to be_nil
    expect(DB[:settlement_transfers].where(id: transfer_id).first[:paid_at]).not_to be_nil
  end

  it "marks a transfer as unpaid" do
    transfer_id = create_transfer(paid_at: Time.now)

    result = described_class.call(
      transfer_id: transfer_id,
      paid: false,
      membership: membership_for(recipient),
      workspace_id: workspace[:id]
    )

    expect(result.success?).to be true
    obj = result.value![:objects].find { |o| o[:objectType] == "settlementTransfer" }
    expect(obj[:paidAt]).to be_nil
    expect(DB[:settlement_transfers].where(id: transfer_id).first[:paid_at]).to be_nil
  end

  it "returns 403 when user is not the recipient" do
    transfer_id = create_transfer

    result = described_class.call(
      transfer_id: transfer_id,
      paid: true,
      membership: membership_for(user),
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("not_recipient")
  end

  it "refuses to mark a superseded transfer as paid" do
    transfer_id = create_transfer
    DB[:settlement_transfers].where(id: transfer_id).update(superseded_at: Time.now)

    result = described_class.call(
      transfer_id: transfer_id,
      paid: true,
      membership: membership_for(recipient),
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("superseded")
  end
end
