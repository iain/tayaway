# typed: true
# frozen_string_literal: true

# Read-only date range model.
class DateRange < T::Struct
  extend T::Sig

  const :id, UUID
  const :event_id, UUID
  const :start_date, Date
  const :end_date, Date
  const :created_at, Time
  const :updated_at, Time

  sig { params(vote_ids: T::Array[String]).returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash(vote_ids:)
    {
      id: id.to_s,
      objectType: "dateRange",
      eventId: event_id.to_s,
      startDate: start_date.iso8601,
      endDate: end_date.iso8601,
      voteIds: vote_ids,
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig

    sig { params(id: T.any(String, UUID)).returns(T.nilable(DateRange)) }
    def find(id)
      DB[:date_ranges].where(id: id).with_row_proc(method(:from_row)).first
    end

    sig { params(event_id: T.any(String, UUID)).returns(T::Array[DateRange]) }
    def for_event(event_id)
      DB[:date_ranges].where(event_id: event_id).order(:start_date).with_row_proc(method(:from_row)).all
    end

    sig { params(event_id: T.any(String, UUID)).returns(T::Array[String]) }
    def ids_for_event(event_id)
      DB[:date_ranges].where(event_id: event_id).order(:start_date).select_map(:id)
    end

    private

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(DateRange) }
    def from_row(row)
      DateRange.new(
        id: UUID.new(row[:id]),
        event_id: UUID.new(row[:event_id]),
        start_date: row[:start_date],
        end_date: row[:end_date],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
