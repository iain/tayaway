# frozen_string_literal: true

# Read-only Expense model.
class Expense < Data.define(:id, :event_id, :user_id, :created_by_user_id, :settlement_id, :reverts_expense_id, :amount, :description, :start_date, :end_date, :created_at, :updated_at)
  class << self
    include Findable

    def find(id)
      dataset.where(id: id).first
    end

    def for_event(event_id)
      dataset.where(event_id: event_id).order(:created_at).limit(ValidationLimits::QUERY_LIMIT).all
    end

    def changed_since(workspace_id, since)
      dataset
        .join(:events, id: :event_id)
        .where(Sequel[:events][:workspace_id] => workspace_id.to_s)
        .where(Sequel.lit("expenses.updated_at > ?", since))
        .select_all(:expenses)
        .all
    end

    private

    def dataset
      DB[:expenses].with_row_proc(method(:from_row))
    end

    def from_row(row)
      new(
        id: UUID.new(row[:id]),
        event_id: UUID.new(row[:event_id]),
        user_id: row[:user_id] ? UUID.new(row[:user_id]) : nil,
        created_by_user_id: row[:created_by_user_id] ? UUID.new(row[:created_by_user_id]) : nil,
        settlement_id: row[:settlement_id] ? UUID.new(row[:settlement_id]) : nil,
        reverts_expense_id: row[:reverts_expense_id] ? UUID.new(row[:reverts_expense_id]) : nil,
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
