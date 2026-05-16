# frozen_string_literal: true

class ExpenseSerializer
  extend PoolObjectSerializer

  class << self
    def broadcast_audiences_for(expense)
      ws_id = DB[:events].where(id: expense.event_id).get(:workspace_id)
      [WS_AUD.call(ws_id)]
    end

    def serialize_batch(expenses, pool:)
      return [] if expenses.empty?
      raise ArgumentError, "ExpenseSerializer requires a non-nil pool for child expansion" unless pool

      expense_ids = expenses.map { |e| e.id.to_s }
      participants_by_expense = ExpenseParticipant.for_expenses(expense_ids)

      all_participants = participants_by_expense.values.flatten
      pool.add(:expense_participant, all_participants) if all_participants.any?

      expenses.map do |expense|
        participants = participants_by_expense[expense.id.to_s] || []
        {
          id: expense.id.to_s,
          objectType: "expense",
          eventId: expense.event_id.to_s,
          userId: expense.user_id&.to_s,
          createdByUserId: expense.created_by_user_id&.to_s,
          settlementId: expense.settlement_id&.to_s,
          revertsExpenseId: expense.reverts_expense_id&.to_s,
          amount: expense.amount,
          description: expense.description,
          startDate: expense.start_date.iso8601,
          endDate: expense.end_date.iso8601,
          participantIds: participants.map { |p| p.id.to_s },
          createdAt: expense.created_at.iso8601(3),
          updatedAt: expense.updated_at.iso8601(3)
        }
      end
    end

    def policy_context_batch(expenses)
      return {} if expenses.empty?

      event_ids = expenses.map { |e| e.event_id.to_s }.uniq
      events_by_id = Event.for_ids(event_ids).each_with_object({}) { |e, h| h[e.id.to_s] = e }

      expenses.each_with_object({}) do |expense, h|
        h[expense.id.to_s] = { event: events_by_id[expense.event_id.to_s] }
      end
    end
  end
end
