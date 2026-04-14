# frozen_string_literal: true

require "spec_helper"

RSpec.describe ExpenseParticipantSerializer do
  let(:workspace) { TestFactories.workspace }
  let(:user) { TestFactories.user }

  describe ".serialize_batch" do
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
      # NOTE: the existing to_api_hash returns created_at for both fields.
      # Preserved for backwards compatibility; fixing is out of scope.
      expect(result[:createdAt]).to eq(result[:updatedAt])
    end
  end
end
