# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Expenses::Update do
  let(:user) { TestFactories.user }
  let(:other_user) { TestFactories.user }
  let(:workspace) { TestFactories.workspace }
  let(:event) { TestFactories.event(workspace: workspace, user: user) }

  # rubocop:disable Sorbet/BlockMethodDefinition -- test helper used across examples
  def create_expense(user_row: user, settlement_id: nil)
    id = SecureRandom.uuid
    now = Time.now
    DB[:expenses].insert(
      id: id,
      event_id: event[:id],
      user_id: user_row[:id],
      settlement_id: settlement_id,
      description: "Original",
      amount: 10.0,
      start_date: Date.new(2026, 1, 1),
      end_date: Date.new(2026, 1, 1),
      created_at: now,
      updated_at: now
    )
    id
  end
  # rubocop:enable Sorbet/BlockMethodDefinition

  it "returns 404 when expense not found" do
    result = described_class.call(
      expense_id: SecureRandom.uuid,
      current_user_id: user[:id],
      workspace_id: workspace[:id],
      description: "New",
      amount: nil
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
      workspace_id: workspace[:id],
      description: "New",
      amount: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Expense is part of a settlement. Delete the settlement first to edit.")
  end

  it "returns 403 when user is not the creator" do
    expense_id = create_expense

    result = described_class.call(
      expense_id: expense_id,
      current_user_id: other_user[:id],
      workspace_id: workspace[:id],
      description: "New",
      amount: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.http_status).to eq(403)
    expect(result.failure.message).to eq("Not authorized to update this expense")
  end

  it "returns failure when no fields provided" do
    expense_id = create_expense

    result = described_class.call(
      expense_id: expense_id,
      current_user_id: user[:id],
      workspace_id: workspace[:id],
      description: nil,
      amount: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Description, amount, or dates are required")
  end

  it "returns failure when description is too long" do
    expense_id = create_expense

    result = described_class.call(
      expense_id: expense_id,
      current_user_id: user[:id],
      workspace_id: workspace[:id],
      description: "a" * 256,
      amount: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Description is too long (maximum 255 characters)")
  end

  it "returns failure when amount is zero or negative" do
    expense_id = create_expense

    result = described_class.call(
      expense_id: expense_id,
      current_user_id: user[:id],
      workspace_id: workspace[:id],
      description: nil,
      amount: 0.0
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Amount must be greater than zero")
  end

  it "returns failure when amount exceeds maximum" do
    expense_id = create_expense

    result = described_class.call(
      expense_id: expense_id,
      current_user_id: user[:id],
      workspace_id: workspace[:id],
      description: nil,
      amount: 1_000_001.0
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Amount cannot exceed 1,000,000")
  end

  it "returns failure when only start_date is provided" do
    expense_id = create_expense

    result = described_class.call(
      expense_id: expense_id,
      current_user_id: user[:id],
      workspace_id: workspace[:id],
      description: nil,
      amount: nil,
      start_date: "2026-01-01",
      end_date: nil
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Both start date and end date are required")
  end

  it "returns failure when start_date is after end_date" do
    expense_id = create_expense

    result = described_class.call(
      expense_id: expense_id,
      current_user_id: user[:id],
      workspace_id: workspace[:id],
      description: nil,
      amount: nil,
      start_date: "2026-01-05",
      end_date: "2026-01-01"
    )

    expect(result.failure?).to be true
    expect(result.failure.message).to eq("Start date must be on or before end date")
  end

  it "updates the description" do
    expense_id = create_expense

    result = described_class.call(
      expense_id: expense_id,
      current_user_id: user[:id],
      workspace_id: workspace[:id],
      description: "Updated",
      amount: nil
    )

    expect(result.success?).to be true
    obj = result.value![:objects].find { |o| o[:objectType] == "expense" }
    expect(obj[:description]).to eq("Updated")
  end

  it "updates the amount" do
    expense_id = create_expense

    result = described_class.call(
      expense_id: expense_id,
      current_user_id: user[:id],
      workspace_id: workspace[:id],
      description: nil,
      amount: 99.99
    )

    expect(result.success?).to be true
    obj = result.value![:objects].find { |o| o[:objectType] == "expense" }
    expect(obj[:amount]).to eq(99.99)
  end

  describe "participant_ids" do
    let(:alice) { TestFactories.user(name: "Alice") }
    let(:bob) { TestFactories.user(name: "Bob") }
    let(:carol) { TestFactories.user(name: "Carol") }

    it "adds participants" do
      expense_id = create_expense

      result = described_class.call(
        expense_id: expense_id,
        current_user_id: user[:id],
        workspace_id: workspace[:id],
        description: nil,
        amount: nil,
        participant_ids: [alice[:id], bob[:id]]
      )

      expect(result.success?).to be true
      participants = result.value![:objects].select { |o| o[:objectType] == "expenseParticipant" }
      expect(participants.map { |p| p[:userId] }).to contain_exactly(alice[:id], bob[:id])

      expense = result.value![:objects].find { |o| o[:objectType] == "expense" }
      expect(expense[:participantIds]).to contain_exactly(*participants.map { |p| p[:id] })
    end

    it "syncs participants: adds new and removes old" do
      expense_id = create_expense
      # Add initial participants
      now = Time.now
      DB[:expense_participants].insert(id: SecureRandom.uuid, expense_id: expense_id, user_id: alice[:id], created_at: now)
      DB[:expense_participants].insert(id: SecureRandom.uuid, expense_id: expense_id, user_id: bob[:id], created_at: now)

      # Update: remove Alice, keep Bob, add Carol
      result = described_class.call(
        expense_id: expense_id,
        current_user_id: user[:id],
        workspace_id: workspace[:id],
        description: nil,
        amount: nil,
        participant_ids: [bob[:id], carol[:id]]
      )

      expect(result.success?).to be true
      participants = result.value![:objects].select { |o| o[:objectType] == "expenseParticipant" }
      expect(participants.map { |p| p[:userId] }).to contain_exactly(bob[:id], carol[:id])
    end

    it "clears all participants when empty array provided" do
      expense_id = create_expense
      now = Time.now
      DB[:expense_participants].insert(id: SecureRandom.uuid, expense_id: expense_id, user_id: alice[:id], created_at: now)

      result = described_class.call(
        expense_id: expense_id,
        current_user_id: user[:id],
        workspace_id: workspace[:id],
        description: nil,
        amount: nil,
        participant_ids: []
      )

      expect(result.success?).to be true
      expense = result.value![:objects].find { |o| o[:objectType] == "expense" }
      expect(expense[:participantIds]).to eq([])
    end

    it "rejects participant changes on settled expense" do
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
        workspace_id: workspace[:id],
        description: nil,
        amount: nil,
        participant_ids: [alice[:id]]
      )

      expect(result.failure?).to be true
      expect(result.failure.message).to include("settlement")
    end
  end
end
