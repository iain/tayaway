# frozen_string_literal: true

class ExpenseParticipantSerializer
  class << self
    def serialize_batch(participants, pool:)
      participants.map do |participant|
        {
          id: participant.id.to_s,
          objectType: "expenseParticipant",
          expenseId: participant.expense_id.to_s,
          userId: participant.user_id.to_s,
          # Note: preserved from original to_api_hash — both fields use created_at.
          createdAt: participant.created_at.iso8601(3),
          updatedAt: participant.created_at.iso8601(3)
        }
      end
    end

    def policy_context(_participant) = {}
    def policy_context_batch(_participants) = {}
  end
end
