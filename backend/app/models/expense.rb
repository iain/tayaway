# typed: true
# frozen_string_literal: true

# Read-only Expense model.
class Expense < T::Struct
  extend T::Sig

  const :id, UUID
  const :event_id, UUID
  const :user_id, T.nilable(UUID)
  const :settlement_id, T.nilable(UUID)
  const :amount, Float
  const :description, String
  const :start_date, Date
  const :end_date, Date
  const :created_at, Time
  const :updated_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash
    {
      id: id.to_s,
      objectType: "expense",
      eventId: event_id.to_s,
      userId: user_id&.to_s,
      settlementId: settlement_id&.to_s,
      amount: amount,
      description: description,
      startDate: start_date.iso8601,
      endDate: end_date.iso8601,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig
    include Result::Methods

    sig { params(id: T.any(String, UUID)).returns(T.nilable(Expense)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(event_id: T.any(String, UUID)).returns(T::Array[Expense]) }
    def for_event(event_id)
      dataset.where(event_id: event_id).order(:created_at).all
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[Expense]) }
    def changed_since(workspace_id, since)
      dataset
        .join(:events, id: :event_id)
        .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
        .where(Sequel.lit("expenses.updated_at > ?", since))
        .select_all(:expenses)
        .all
    end

    sig { params(id: T.any(String, UUID)).returns(Result[Expense, ServiceError]) }
    def find_result(id)
      expense = find(id)
      if expense
        T.cast(Success(expense), Result[Expense, ServiceError])
      elsif DB[:deleted_items].where(object_type: "expense", object_id: id).first
        T.cast(Failure(ServiceError.gone("Expense not found")), Result[Expense, ServiceError])
      else
        T.cast(Failure(ServiceError.not_found("Expense not found")), Result[Expense, ServiceError])
      end
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:expenses].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(Expense) }
    def from_row(row)
      Expense.new(
        id: UUID.new(row[:id]),
        event_id: UUID.new(row[:event_id]),
        user_id: row[:user_id] ? UUID.new(row[:user_id]) : nil,
        settlement_id: row[:settlement_id] ? UUID.new(row[:settlement_id]) : nil,
        amount: row[:amount].to_f,
        description: row[:description],
        start_date: row[:start_date],
        end_date: row[:end_date],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
