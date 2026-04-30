# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::MarkNetPaid do
  let(:workspace) { TestFactories.workspace }
  let(:alice) { TestFactories.user(name: "Alice") }
  let(:bob)   { TestFactories.user(name: "Bob") }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  def create_transfer(event:, from:, to:, amount:, paid_at: nil)
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
      paid_at: paid_at,
      created_at: now,
      updated_at: now
    )
    transfer_id
  end

  it "marks every underlying transfer paid in one shot" do
    event1 = TestFactories.event(workspace: workspace, user: alice)
    event2 = TestFactories.event(workspace: workspace, user: alice)
    t1 = create_transfer(event: event1, from: alice, to: bob, amount: 50.0)
    t2 = create_transfer(event: event2, from: bob, to: alice, amount: 10.0)

    # Net is alice→bob 40. Bob is the recipient and is the one who calls.
    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: alice[:id],
      expected_amount: 40.0,
      membership: membership_for(bob)
    )

    expect(result.success?).to be true
    expect(DB[:settlement_transfers].where(id: t1).get(:paid_at)).not_to be_nil
    expect(DB[:settlement_transfers].where(id: t2).get(:paid_at)).not_to be_nil

    objects = result.value![:objects].select { |o| o[:objectType] == "settlementTransfer" }
    expect(objects.map { |o| o[:id] }).to contain_exactly(t1, t2)
  end

  it "lets the net sender mark paid (sender attestation)" do
    event = TestFactories.event(workspace: workspace, user: alice)
    create_transfer(event: event, from: alice, to: bob, amount: 50.0)

    # Net is alice→bob 50. Alice attests after she's paid Bob.
    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: bob[:id],
      expected_amount: 50.0,
      membership: membership_for(alice)
    )

    expect(result.success?).to be true
    row = DB[:settlement_transfers].first
    expect(row[:paid_at]).not_to be_nil
    expect(row[:paid_by_user_id]).to eq(alice[:id])
  end

  it "records paid_by_user_id when the recipient marks paid" do
    event = TestFactories.event(workspace: workspace, user: alice)
    t = create_transfer(event: event, from: alice, to: bob, amount: 50.0)

    described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: alice[:id],
      expected_amount: 50.0,
      membership: membership_for(bob)
    )

    expect(DB[:settlement_transfers].where(id: t).get(:paid_by_user_id)).to eq(bob[:id])
  end

  it "treats a bystander as having no balance with the named counterparty" do
    # Bystanders aren't a separate auth code path — by construction the
    # composable computes the (caller, counterparty) pair, which for a
    # third party has no active transfers. They get the same "nothing to
    # settle" 409 anyone hitting an empty pair would.
    event = TestFactories.event(workspace: workspace, user: alice)
    create_transfer(event: event, from: alice, to: bob, amount: 50.0)
    bystander = TestFactories.user(name: "Bystander")

    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: alice[:id],
      expected_amount: 50.0,
      membership: membership_for(bystander)
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(409)
    expect(result.failure.message).to include("Nothing to settle")
  end

  it "rejects when the expected amount no longer matches the live net" do
    event = TestFactories.event(workspace: workspace, user: alice)
    create_transfer(event: event, from: alice, to: bob, amount: 50.0)

    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: alice[:id],
      expected_amount: 40.0,
      membership: membership_for(bob)
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(409)
    expect(result.failure.message).to include("Balance has changed")
  end

  it "rejects when there's no active balance with the counterparty" do
    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: alice[:id],
      expected_amount: 40.0,
      membership: membership_for(bob)
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(409)
    expect(result.failure.message).to include("Nothing to settle")
  end

  it "rejects self-counterparty" do
    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: alice[:id],
      expected_amount: 0.0,
      membership: membership_for(alice)
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(400)
  end

  it "validates required inputs" do
    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: nil,
      expected_amount: 40.0,
      membership: membership_for(bob)
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(400)
  end

  it "leaves transfers paid earlier untouched and only marks the active set" do
    event1 = TestFactories.event(workspace: workspace, user: alice)
    event2 = TestFactories.event(workspace: workspace, user: alice)
    earlier_paid_at = Time.now - 3600
    paid = create_transfer(event: event1, from: alice, to: bob, amount: 50.0, paid_at: earlier_paid_at)
    fresh = create_transfer(event: event2, from: alice, to: bob, amount: 25.0)

    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: alice[:id],
      expected_amount: 25.0,
      membership: membership_for(bob)
    )

    expect(result.success?).to be true
    expect(DB[:settlement_transfers].where(id: fresh).get(:paid_at)).not_to be_nil
    # The previously-paid transfer's timestamp must not be overwritten.
    expect(DB[:settlement_transfers].where(id: paid).get(:paid_at).to_i)
      .to eq(earlier_paid_at.to_i)
  end
end
