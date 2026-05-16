# frozen_string_literal: true

class ExpenseParticipantSerializer
  extend PoolObjectSerializer

  class << self
    def topics_for(participant)
      ws_id = DB[:expenses]
              .join(:events, id: :event_id)
              .where(Sequel[:expenses][:id] => participant.expense_id)
              .get(Sequel[:events][:workspace_id])
      ["workspace:#{ws_id}"]
    end

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
