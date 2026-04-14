# frozen_string_literal: true

class ExpenseSerializer
  extend PoolObjectSerializer

  class << self
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
          settlementId: expense.settlement_id&.to_s,
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
  end
end
