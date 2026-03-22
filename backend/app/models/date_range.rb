# typed: true
# frozen_string_literal: true

# Read-only date range model.
class DateRange < T::Struct
  extend T::Sig

  const :id, UUID
  const :date_poll_id, UUID
  const :start_date, Date
  const :end_date, Date
  const :created_at, Time
  const :updated_at, Time

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash
    {
      id: id.to_s,
      objectType: "dateRange",
      datePollId: date_poll_id.to_s,
      startDate: start_date.iso8601,
      endDate: end_date.iso8601,
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig

    sig { params(id: T.any(String, UUID)).returns(T.nilable(DateRange)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(date_poll_id: T.any(String, UUID)).returns(T::Array[DateRange]) }
    def for_date_poll(date_poll_id)
      dataset.where(date_poll_id: date_poll_id).order(:start_date).all
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[DateRange]) }
    def changed_since(workspace_id, since)
      dataset
        .join(:date_polls, id: :date_poll_id)
        .join(:events, id: Sequel[:date_polls][:event_id])
        .where(Sequel[:events][:workspace_id] => workspace_id)
        .where(Sequel.lit("date_ranges.updated_at > ?", since))
        .select_all(:date_ranges)
        .all
    end

    sig { params(date_poll_id: T.any(String, UUID)).returns(T::Array[String]) }
    def ids_for_date_poll(date_poll_id)
      DB[:date_ranges].where(date_poll_id: date_poll_id).order(:start_date).select_map(:id)
    end

    sig { params(date_poll_ids: T::Array[String]).returns(T::Hash[String, T::Array[String]]) }
    def ids_for_date_poll_ids(date_poll_ids)
      return {} if date_poll_ids.empty?

      DB[:date_ranges]
        .where(date_poll_id: date_poll_ids)
        .order(:start_date)
        .select_map([:date_poll_id, :id])
        .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(poll_id, id), h| h[poll_id.to_s] << id.to_s }
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:date_ranges].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(DateRange) }
    def from_row(row)
      DateRange.new(
        id: UUID.new(row[:id]),
        date_poll_id: UUID.new(row[:date_poll_id]),
        start_date: row[:start_date],
        end_date: row[:end_date],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
