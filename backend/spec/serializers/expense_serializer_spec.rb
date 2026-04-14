# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExpenseSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:event_row) { TestFactories.event(workspace: workspace, user: user) }
      let(:pool_object) do
        now = Time.now
        expense_id = SecureRandom.uuid
        DB[:expenses].insert(
          id: expense_id, event_id: event_row[:id], user_id: user[:id],
          description: "Test", amount: 1.0, start_date: Date.today, end_date: Date.today,
          created_at: now, updated_at: now
        )
        pool = PoolSerializer.new(workspace_id: workspace[:id])
        described_class.serialize_batch([Expense.find(expense_id)], pool: pool).first
      end

      it_behaves_like "a pool object with createdAt", "expense"
    end

    it "serializes expense fields with batched participantIds" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      expense_id = SecureRandom.uuid
      DB[:expenses].insert(
        id: expense_id, event_id: event[:id], user_id: user[:id],
        description: "Pizza", amount: 25.0,
        start_date: Date.today, end_date: Date.today,
        created_at: now, updated_at: now
      )
      participant_id = SecureRandom.uuid
      DB[:expense_participants].insert(
        id: participant_id, expense_id: expense_id, user_id: user[:id], created_at: now
      )
      expense = Expense.find(expense_id)
      pool = PoolSerializer.new(workspace_id: workspace[:id])

      result = described_class.serialize_batch([expense], pool: pool).first

      expect(result[:id]).to eq(expense.id.to_s)
      expect(result[:objectType]).to eq("expense")
      expect(result[:eventId]).to eq(event[:id].to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
      expect(result[:amount]).to eq(25.0)
      expect(result[:description]).to eq("Pizza")
      expect(result[:participantIds]).to include(participant_id.to_s)
    end

    it "adds participants to the pool when pool is provided" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      expense_id = SecureRandom.uuid
      DB[:expenses].insert(
        id: expense_id, event_id: event[:id], user_id: user[:id],
        description: "x", amount: 1.0, start_date: Date.today, end_date: Date.today,
        created_at: now, updated_at: now
      )
      participant_id = SecureRandom.uuid
      DB[:expense_participants].insert(
        id: participant_id, expense_id: expense_id, user_id: user[:id], created_at: now
      )
      expense = Expense.find(expense_id)

      pool = PoolSerializer.new(workspace_id: workspace[:id])
      pool.add(:expense, [expense])

      participants = pool.to_a.select { |o| o[:objectType] == "expenseParticipant" }
      expect(participants.map { |o| o[:id] }).to include(participant_id.to_s)
    end

    it "raises when pool is nil — child expansion would be silently skipped" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      expense_id = SecureRandom.uuid
      DB[:expenses].insert(
        id: expense_id, event_id: event[:id], user_id: user[:id],
        description: "x", amount: 1.0, start_date: Date.today, end_date: Date.today,
        created_at: now, updated_at: now
      )
      expense = Expense.find(expense_id)

      expect { described_class.serialize_batch([expense], pool: nil) }
        .to raise_error(ArgumentError, /requires a non-nil pool/)
    end
  end
end
