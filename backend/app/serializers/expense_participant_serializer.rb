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
          factor: participant.factor,
          createdAt: participant.created_at.iso8601(3),
          updatedAt: participant.updated_at.iso8601(3)
        }
      end
    end
  end
end
