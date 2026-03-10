# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Settlements::Delete do
  let(:creator) { TestFactories.user }
  let(:event_owner) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:event) { TestFactories.event(workspace: workspace, user: event_owner) }

  # rubocop:disable Sorbet/BlockMethodDefinition -- test helper used across examples
  def create_settlement(user_row: creator, with_expense: false, with_transfer: false)
    settlement_id = SecureRandom.uuid
    now = Time.now
    DB[:settlements].insert(
      id: settlement_id,
      event_id: event[:id],
      user_id: user_row[:id],
      created_at: now,
      updated_at: now
    )

    if with_expense
      expense_id = SecureRandom.uuid
      DB[:expenses].insert(
        id: expense_id,
        event_id: event[:id],
        user_id: creator[:id],
        settlement_id: settlement_id,
        description: "Lunch",
        amount: 30.0,
        start_date: Date.new(2026, 1, 1),
        end_date: Date.new(2026, 1, 1),
        created_at: now,
        updated_at: now
      )
    end

    if with_transfer
      transfer_id = SecureRandom.uuid
      DB[:settlement_transfers].insert(
        id: transfer_id,
        settlement_id: settlement_id,
        from_user_id: other_user[:id],
        to_user_id: creator[:id],
        amount: 15.0,
        created_at: now,
        updated_at: now
      )
    end

    settlement_id
  end
  # rubocop:enable Sorbet/BlockMethodDefinition

  it "returns 404 when settlement not found" do
    result = described_class.call(
      settlement_id: SecureRandom.uuid,
      current_user_id: creator[:id],
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
  end

  it "returns 403 when user is neither creator nor event owner" do
    settlement_id = create_settlement

    result = described_class.call(
      settlement_id: settlement_id,
      current_user_id: other_user[:id],
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("Not authorized to delete this settlement")
  end

  it "allows the settlement creator to delete" do
    settlement_id = create_settlement

    result = described_class.call(
      settlement_id: settlement_id,
      current_user_id: creator[:id],
      workspace_id: workspace[:id]
    )

    expect(result.success?).to be true
    expect(DB[:settlements].where(id: settlement_id).count).to eq(0)
  end

  it "allows the event owner to delete" do
    settlement_id = create_settlement

    result = described_class.call(
      settlement_id: settlement_id,
      current_user_id: event_owner[:id],
      workspace_id: workspace[:id]
    )

    expect(result.success?).to be true
    expect(DB[:settlements].where(id: settlement_id).count).to eq(0)
  end

  it "unlocks expenses (clears settlement_id) when deleting" do
    settlement_id = create_settlement(with_expense: true)
    expense = DB[:expenses].where(settlement_id: settlement_id).first

    described_class.call(
      settlement_id: settlement_id,
      current_user_id: creator[:id],
      workspace_id: workspace[:id]
    )

    updated = DB[:expenses].where(id: expense[:id]).first
    expect(updated[:settlement_id]).to be_nil
  end

  it "returns deleted items including the settlement and its transfers" do
    settlement_id = create_settlement(with_transfer: true)
    transfer = DB[:settlement_transfers].where(settlement_id: settlement_id).first

    result = described_class.call(
      settlement_id: settlement_id,
      current_user_id: creator[:id],
      workspace_id: workspace[:id]
    )

    expect(result.success?).to be true
    deleted = result.value![:deleted]
    expect(deleted).to include(hash_including(objectType: "settlement", id: settlement_id.to_s))
    expect(deleted).to include(hash_including(objectType: "settlementTransfer", id: transfer[:id].to_s))
  end

  it "inserts deleted_items records for the settlement" do
    settlement_id = create_settlement

    described_class.call(
      settlement_id: settlement_id,
      current_user_id: creator[:id],
      workspace_id: workspace[:id]
    )

    expect(DB[:deleted_items].where(object_type: "settlement", object_id: settlement_id).count).to eq(1)
  end
end
