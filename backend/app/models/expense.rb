# frozen_string_literal: true

# Read-only Expense model.
class Expense
  attr_reader :id, :event_id, :user_id, :settlement_id, :amount, :description, :start_date, :end_date, :created_at, :updated_at

  def initialize(
    id:,
    event_id:,
    user_id:,
    settlement_id:,
    amount:,
    description:,
    start_date:,
    end_date:,
    created_at:,
    updated_at:
  )
    @id = id
    @event_id = event_id
    @user_id = user_id
    @settlement_id = settlement_id
    @amount = amount
    @description = description
    @start_date = start_date
    @end_date = end_date
    @created_at = created_at
    @updated_at = updated_at
  end

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
    include Dry::Monads[:result]
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
