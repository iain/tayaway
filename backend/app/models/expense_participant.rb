# frozen_string_literal: true

# Read-only ExpenseParticipant model.
class ExpenseParticipant
  attr_reader :id, :expense_id, :user_id, :created_at

  def initialize(
    id:,
    expense_id:,
    user_id:,
    created_at:
  )
    @id = id
    @expense_id = expense_id
    @user_id = user_id
    @created_at = created_at
  end

  def to_api_hash
    {
      id: id.to_s,
      objectType: "expenseParticipant",
      expenseId: expense_id.to_s,
      userId: user_id.to_s,
      createdAt: created_at.iso8601(3),
      updatedAt: created_at.iso8601(3)
    }
  end

  class << self
    include Result::Methods
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_expense(expense_id)
      dataset.where(expense_id: expense_id).all
    end

    def for_expenses(expense_ids)
      return {} if expense_ids.empty?

      dataset.where(expense_id: expense_ids).all.group_by { |p| p.expense_id.to_s }
    end

    def user_ids_for_expense(expense_id)
      DB[:expense_participants].where(expense_id: expense_id).select_map(:user_id).map(&:to_s)
    end

    def changed_since(workspace_id, since)
      dataset
        .join(:expenses, id: :expense_id)
        .join(:events, id: Sequel[:expenses][:event_id])
        .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
        .where(Sequel.lit("expense_participants.created_at > ?", since))
        .select_all(:expense_participants)
        .all
    end

    private

    def dataset
      DB[:expense_participants].with_row_proc(method(:from_row))
    end

    def from_row(row)
      ExpenseParticipant.new(
        id: UUID.new(row[:id]),
        expense_id: UUID.new(row[:expense_id]),
        user_id: UUID.new(row[:user_id]),
        created_at: row[:created_at]
      )
    end
  end
end
