# frozen_string_literal: true

require "spec_helper"

RSpec.describe Expenses::Delete do
  let(:user) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:event) { TestFactories.event(workspace: workspace, user: user) }

  # -- test helper used across examples
  def create_expense(user_row: user, settlement_id: nil)
    id = SecureRandom.uuid
    now = Time.now
    DB[:expenses].insert(
      id: id,
      event_id: event[:id],
      user_id: user_row[:id],
      settlement_id: settlement_id,
      description: "Dinner",
      amount: 20.0,
      start_date: Date.new(2026, 1, 1),
      end_date: Date.new(2026, 1, 1),
      created_at: now,
      updated_at: now
    )
    id
  end
  it "returns 404 when expense not found" do
    result = described_class.call(
      expense_id: SecureRandom.uuid,
      current_user_id: user[:id],
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(404)
  end

  it "returns failure when expense is part of a settlement" do
    settlement_id = SecureRandom.uuid
    now = Time.now
    DB[:settlements].insert(
      id: settlement_id,
      event_id: event[:id],
      user_id: user[:id],
      created_at: now,
      updated_at: now
    )
    expense_id = create_expense(settlement_id: settlement_id)

    result = described_class.call(
      expense_id: expense_id,
      current_user_id: user[:id],
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Expense is part of a settlement. Delete the settlement first to edit.")
  end

  it "returns 403 when user is not the creator" do
    expense_id = create_expense

    result = described_class.call(
      expense_id: expense_id,
      current_user_id: other_user[:id],
      workspace_id: workspace[:id]
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("Not authorized to delete this expense")
  end

  it "deletes the expense and returns deleted payload" do
    expense_id = create_expense

    result = described_class.call(
      expense_id: expense_id,
      current_user_id: user[:id],
      workspace_id: workspace[:id]
    )

    expect(result.success?).to be true
    expect(result.value![:deleted]).to eq([{ objectType: "expense", id: expense_id.to_s }])
    expect(DB[:expenses].where(id: expense_id).count).to eq(0)
  end

  it "inserts a deleted_items record" do
    expense_id = create_expense

    described_class.call(
      expense_id: expense_id,
      current_user_id: user[:id],
      workspace_id: workspace[:id]
    )

    expect(DB[:deleted_items].where(object_type: "expense", object_id: expense_id).count).to eq(1)
  end
end
