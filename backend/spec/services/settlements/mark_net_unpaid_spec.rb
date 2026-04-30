# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::MarkNetUnpaid do
  let(:workspace) { TestFactories.workspace }
  let(:alice) { TestFactories.user(name: "Alice") }
  let(:bob)   { TestFactories.user(name: "Bob") }

  def membership_for(usr)
    row = TestFactories.workspace_membership(workspace: workspace, user: usr)
    WorkspaceMembership.find(row[:id])
  end

  def create_transfer(event:, from:, to:, amount:, paid_at: Time.now, paid_by: nil)
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
      paid_by_user_id: paid_by ? paid_by[:id] : nil,
      created_at: now,
      updated_at: now
    )
    transfer_id
  end

  it "clears paid_at and paid_by_user_id on the named rows" do
    event = TestFactories.event(workspace: workspace, user: alice)
    t = create_transfer(event: event, from: alice, to: bob, amount: 50.0, paid_by: alice)

    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: bob[:id],
      transfer_ids: [t],
      membership: membership_for(alice)
    )

    expect(result.success?).to be true
    row = DB[:settlement_transfers].where(id: t).first
    expect(row[:paid_at]).to be_nil
    expect(row[:paid_by_user_id]).to be_nil
  end

  it "lets the recipient unmark too" do
    event = TestFactories.event(workspace: workspace, user: alice)
    t = create_transfer(event: event, from: alice, to: bob, amount: 50.0, paid_by: alice)

    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: alice[:id],
      transfer_ids: [t],
      membership: membership_for(bob)
    )

    expect(result.success?).to be true
    expect(DB[:settlement_transfers].where(id: t).get(:paid_at)).to be_nil
  end

  it "ignores transfer ids that don't match the workspace + pair" do
    event_a = TestFactories.event(workspace: workspace, user: alice)
    event_b = TestFactories.event(workspace: workspace, user: alice)
    t_real = create_transfer(event: event_a, from: alice, to: bob, amount: 50.0)
    foreign_user = TestFactories.user(name: "Foreign")
    t_other_pair = create_transfer(event: event_b, from: alice, to: foreign_user, amount: 10.0)

    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: bob[:id],
      transfer_ids: [t_real, t_other_pair],
      membership: membership_for(alice)
    )

    expect(result.success?).to be true
    expect(DB[:settlement_transfers].where(id: t_real).get(:paid_at)).to be_nil
    # The unrelated pair's transfer was filtered out, not unmarked.
    expect(DB[:settlement_transfers].where(id: t_other_pair).get(:paid_at)).not_to be_nil
  end

  it "rejects when no rows match" do
    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: bob[:id],
      transfer_ids: [SecureRandom.uuid],
      membership: membership_for(alice)
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(409)
  end

  it "blocks unmarking a transfer whose settlement has a successor" do
    event = TestFactories.event(workspace: workspace, user: alice)
    t = create_transfer(event: event, from: alice, to: bob, amount: 50.0, paid_by: alice)
    settlement_id = DB[:settlement_transfers].where(id: t).get(:settlement_id)
    DB[:settlements].insert(
      id: SecureRandom.uuid,
      event_id: event[:id],
      user_id: alice[:id],
      previous_settlement_id: settlement_id,
      created_at: Time.now,
      updated_at: Time.now
    )

    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: bob[:id],
      transfer_ids: [t],
      membership: membership_for(alice)
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("locked_in_followup")
    expect(DB[:settlement_transfers].where(id: t).get(:paid_at)).not_to be_nil
  end

  it "validates required inputs" do
    result = described_class.call(
      workspace_id: workspace[:id],
      counterparty_user_id: bob[:id],
      transfer_ids: [],
      membership: membership_for(alice)
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(400)
  end
end
