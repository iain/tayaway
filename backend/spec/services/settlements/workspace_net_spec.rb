# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::WorkspaceNet do
  let(:workspace) { TestFactories.workspace }
  let(:other_workspace) { TestFactories.workspace }
  let(:alice) { TestFactories.user(name: "Alice") }
  let(:bob)   { TestFactories.user(name: "Bob") }

  def create_transfer(event:, from:, to:, amount:, paid_at: nil, superseded_at: nil)
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
      superseded_at: superseded_at,
      created_at: now,
      updated_at: now
    )
    transfer_id
  end

  it "returns nil when no transfers exist between the pair" do
    result = described_class.compute_pair(
      workspace_id: workspace[:id],
      user_a: alice[:id],
      user_b: bob[:id]
    )
    expect(result).to be_nil
  end

  it "returns nil when comparing a user with themselves" do
    result = described_class.compute_pair(
      workspace_id: workspace[:id],
      user_a: alice[:id],
      user_b: alice[:id]
    )
    expect(result).to be_nil
  end

  it "nets opposite directions across events" do
    event1 = TestFactories.event(workspace: workspace, user: alice)
    event2 = TestFactories.event(workspace: workspace, user: alice)
    t1 = create_transfer(event: event1, from: alice, to: bob, amount: 50.0)
    t2 = create_transfer(event: event2, from: bob, to: alice, amount: 10.0)

    result = described_class.compute_pair(
      workspace_id: workspace[:id],
      user_a: alice[:id],
      user_b: bob[:id]
    )

    expect(result).not_to be_nil
    expect(result[:from_user_id]).to eq(alice[:id])
    expect(result[:to_user_id]).to eq(bob[:id])
    expect(result[:amount]).to eq(40.0)
    expect(result[:underlying_transfer_ids]).to contain_exactly(t1, t2)
  end

  it "sums same-direction transfers across events" do
    event1 = TestFactories.event(workspace: workspace, user: alice)
    event2 = TestFactories.event(workspace: workspace, user: alice)
    create_transfer(event: event1, from: alice, to: bob, amount: 25.0)
    create_transfer(event: event2, from: alice, to: bob, amount: 15.0)

    result = described_class.compute_pair(
      workspace_id: workspace[:id],
      user_a: alice[:id],
      user_b: bob[:id]
    )

    expect(result[:from_user_id]).to eq(alice[:id])
    expect(result[:to_user_id]).to eq(bob[:id])
    expect(result[:amount]).to eq(40.0)
  end

  it "returns nil when opposite directions cancel exactly" do
    event1 = TestFactories.event(workspace: workspace, user: alice)
    event2 = TestFactories.event(workspace: workspace, user: alice)
    create_transfer(event: event1, from: alice, to: bob, amount: 30.0)
    create_transfer(event: event2, from: bob, to: alice, amount: 30.0)

    result = described_class.compute_pair(
      workspace_id: workspace[:id],
      user_a: alice[:id],
      user_b: bob[:id]
    )

    expect(result).to be_nil
  end

  it "ignores paid transfers" do
    event = TestFactories.event(workspace: workspace, user: alice)
    create_transfer(event: event, from: alice, to: bob, amount: 50.0, paid_at: Time.now)

    result = described_class.compute_pair(
      workspace_id: workspace[:id],
      user_a: alice[:id],
      user_b: bob[:id]
    )

    expect(result).to be_nil
  end

  it "ignores superseded transfers" do
    event = TestFactories.event(workspace: workspace, user: alice)
    create_transfer(event: event, from: alice, to: bob, amount: 50.0, superseded_at: Time.now)

    result = described_class.compute_pair(
      workspace_id: workspace[:id],
      user_a: alice[:id],
      user_b: bob[:id]
    )

    expect(result).to be_nil
  end

  it "scopes to the requested workspace" do
    other_event = TestFactories.event(workspace: other_workspace, user: alice)
    create_transfer(event: other_event, from: alice, to: bob, amount: 50.0)

    result = described_class.compute_pair(
      workspace_id: workspace[:id],
      user_a: alice[:id],
      user_b: bob[:id]
    )

    expect(result).to be_nil
  end

  it "is direction-agnostic in its arguments" do
    event = TestFactories.event(workspace: workspace, user: alice)
    create_transfer(event: event, from: alice, to: bob, amount: 50.0)

    a_first = described_class.compute_pair(
      workspace_id: workspace[:id],
      user_a: alice[:id],
      user_b: bob[:id]
    )
    b_first = described_class.compute_pair(
      workspace_id: workspace[:id],
      user_a: bob[:id],
      user_b: alice[:id]
    )

    expect(a_first[:from_user_id]).to eq(alice[:id])
    expect(a_first[:to_user_id]).to eq(bob[:id])
    expect(b_first[:from_user_id]).to eq(alice[:id])
    expect(b_first[:to_user_id]).to eq(bob[:id])
    expect(a_first[:amount]).to eq(b_first[:amount])
  end
end
