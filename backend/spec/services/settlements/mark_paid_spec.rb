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

  it "lets the sender mark a transfer as paid (sender attestation)" do
    transfer_id = create_transfer

    result = described_class.call(
      transfer_id: transfer_id,
      paid: true,
      membership: membership_for(user),
      workspace_id: workspace[:id]
    )

    expect(result.success?).to be true
    row = DB[:settlement_transfers].where(id: transfer_id).first
    expect(row[:paid_at]).not_to be_nil
    expect(row[:paid_by_user_id]).to eq(user[:id])
  end

  it "records the recipient on paid_by_user_id when they mark paid" do
    transfer_id = create_transfer

    result = described_class.call(
      transfer_id: transfer_id,
      paid: true,
      membership: membership_for(recipient),
      workspace_id: workspace[:id]
    )

    expect(result.success?).to be true
    expect(DB[:settlement_transfers].where(id: transfer_id).get(:paid_by_user_id)).to eq(recipient[:id])
  end

  it "clears paid_by_user_id when unmarked" do
    transfer_id = create_transfer(paid_at: Time.now)
    DB[:settlement_transfers].where(id: transfer_id).update(paid_by_user_id: recipient[:id])

    result = described_class.call(
      transfer_id: transfer_id,
      paid: false,
      membership: membership_for(recipient),
      workspace_id: workspace[:id]
    )

    expect(result.success?).to be true
    expect(DB[:settlement_transfers].where(id: transfer_id).get(:paid_by_user_id)).to be_nil
  end

  it "returns 403 when user is neither sender nor recipient" do
    transfer_id = create_transfer
    bystander = TestFactories.user(name: "Bystander")
    bystander_membership = WorkspaceMembership.find(
      TestFactories.workspace_membership(workspace: workspace, user: bystander)[:id]
    )

    result = described_class.call(
      transfer_id: transfer_id,
      paid: true,
      membership: bystander_membership,
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("not_pair_member")
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

  it "refuses to unmark a paid transfer once a follow-up settlement exists" do
    transfer_id = create_transfer(paid_at: Time.now)
    settlement_id = DB[:settlement_transfers].where(id: transfer_id).get(:settlement_id)
    DB[:settlements].insert(
      id: SecureRandom.uuid,
      event_id: event[:id],
      user_id: user[:id],
      previous_settlement_id: settlement_id,
      created_at: Time.now,
      updated_at: Time.now
    )

    result = described_class.call(
      transfer_id: transfer_id,
      paid: false,
      membership: membership_for(recipient),
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("locked_in_followup")
    expect(DB[:settlement_transfers].where(id: transfer_id).get(:paid_at)).not_to be_nil
  end

  it "blocks both directions of the toggle once a follow-up settlement exists" do
    # The policy is direction-blind: a follow-up settlement makes the chain
    # math depend on this transfer being paid, so even an idempotent
    # paid=true click is rejected — the UI should show the locked-in modal
    # instead of routing through to the service.
    transfer_id = create_transfer(paid_at: Time.now)
    settlement_id = DB[:settlement_transfers].where(id: transfer_id).get(:settlement_id)
    DB[:settlements].insert(
      id: SecureRandom.uuid,
      event_id: event[:id],
      user_id: user[:id],
      previous_settlement_id: settlement_id,
      created_at: Time.now,
      updated_at: Time.now
    )

    result = described_class.call(
      transfer_id: transfer_id,
      paid: true,
      membership: membership_for(recipient),
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("locked_in_followup")
  end

  it "reports a deleted-settlement conflict distinctly from supersede" do
    transfer_id = create_transfer
    transfer = SettlementTransfer.find(transfer_id)
    settlement_id = transfer.settlement_id
    # Simulate the row being yanked between policy check and the locked
    # update — same observable outcome the deleted-settlement cascade
    # produces.
    DB[:settlement_transfers].where(id: transfer_id).delete
    DB[:settlements].where(id: settlement_id).delete

    result = described_class.send(:update_paid, transfer, true, workspace[:id], membership_for(recipient))

    expect(result.failure?).to be true
    expect(result.failure.message).to include("no longer exists")
  end
end
