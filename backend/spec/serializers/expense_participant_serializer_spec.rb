# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExpenseParticipantSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
    context "when serializing a single object" do
      subject { pool_object }

      let(:pool_object) do
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
        described_class.serialize_batch([ExpenseParticipant.find(participant_id)], pool: nil).first
      end

      it_behaves_like "a pool object with createdAt", "expenseParticipant"
    end

    it "serializes participant fields" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      expense_id = SecureRandom.uuid
      DB[:expenses].insert(
        id: expense_id, event_id: event[:id], user_id: user[:id],
        description: "x", amount: 5.0, start_date: Date.today, end_date: Date.today,
        created_at: now, updated_at: now
      )
      participant_id = SecureRandom.uuid
      DB[:expense_participants].insert(
        id: participant_id, expense_id: expense_id, user_id: user[:id], created_at: now
      )
      participant = ExpenseParticipant.find(participant_id)

      result = described_class.serialize_batch([participant], pool: nil).first

      expect(result[:id]).to eq(participant.id.to_s)
      expect(result[:objectType]).to eq("expenseParticipant")
      expect(result[:expenseId]).to eq(expense_id.to_s)
      expect(result[:userId]).to eq(user[:id].to_s)
    end

    it "emits distinct createdAt and updatedAt when the row has been updated" do
      event = TestFactories.event(workspace: workspace, user: user)
      created = Time.now - 60
      updated = Time.now
      expense_id = SecureRandom.uuid
      DB[:expenses].insert(
        id: expense_id, event_id: event[:id], user_id: user[:id],
        description: "x", amount: 5.0, start_date: Date.today, end_date: Date.today,
        created_at: created, updated_at: created
      )
      participant_id = SecureRandom.uuid
      DB[:expense_participants].insert(
        id: participant_id, expense_id: expense_id, user_id: user[:id],
        created_at: created, updated_at: updated
      )
      participant = ExpenseParticipant.find(participant_id)

      result = described_class.serialize_batch([participant], pool: nil).first

      expect(Time.iso8601(result[:updatedAt])).to be > Time.iso8601(result[:createdAt])
    end

    it "serializes the factor field" do
      event = TestFactories.event(workspace: workspace, user: user)
      now = Time.now
      expense_id = SecureRandom.uuid
      DB[:expenses].insert(
        id: expense_id, event_id: event[:id], user_id: user[:id],
        description: "x", amount: 10.0, start_date: Date.today, end_date: Date.today,
        created_at: now, updated_at: now
      )
      participant_id = SecureRandom.uuid
      DB[:expense_participants].insert(
        id: participant_id, expense_id: expense_id, user_id: user[:id],
        factor: 2.5, created_at: now
      )
      participant = ExpenseParticipant.find(participant_id)

      result = described_class.serialize_batch([participant], pool: nil).first

      expect(result[:factor]).to eq(2.5)
    end
  end
end
