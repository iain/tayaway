# typed: true
# frozen_string_literal: true

# Read-only ExpenseParticipant model.
class ExpenseParticipant < T::Struct
  extend T::Sig

  const :id, UUID
  const :expense_id, UUID
  const :user_id, UUID
  const :created_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
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
    extend T::Sig
    include Result::Methods
    include Findable

    sig { params(id: T.any(String, UUID)).returns(T.nilable(ExpenseParticipant)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(expense_id: T.any(String, UUID)).returns(T::Array[ExpenseParticipant]) }
    def for_expense(expense_id)
      dataset.where(expense_id: expense_id).all
    end

    sig { params(expense_ids: T::Array[String]).returns(T::Hash[String, T::Array[ExpenseParticipant]]) }
    def for_expenses(expense_ids)
      return {} if expense_ids.empty?

      dataset.where(expense_id: expense_ids).all.group_by { |p| p.expense_id.to_s }
    end

    sig { params(expense_id: T.any(String, UUID)).returns(T::Array[String]) }
    def user_ids_for_expense(expense_id)
      DB[:expense_participants].where(expense_id: expense_id).select_map(:user_id).map(&:to_s)
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[ExpenseParticipant]) }
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

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:expense_participants].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(ExpenseParticipant) }
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
