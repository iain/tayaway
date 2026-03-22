# typed: true
# frozen_string_literal: true

# Read-only date poll model.
class DatePoll < T::Struct
  extend T::Sig

  const :id, UUID
  const :event_id, UUID
  const :deadline, Time
  const :selected_date_range_id, T.nilable(UUID)
  const :closed_at, T.nilable(Time)
  const :created_at, Time
  const :updated_at, Time

  sig { returns(String) }
  def status
    if closed_at
      "resolved"
    elsif deadline < Time.now
      "expired"
    else
      "open"
    end
  end

  sig { returns(T::Boolean) }
  def open?
    status == "open"
  end

  sig { params(date_range_ids: T::Array[String]).returns(T::Hash[Symbol, T.untyped]) }
  def to_api_hash(date_range_ids:)
    {
      id: id.to_s,
      objectType: "datePoll",
      eventId: event_id.to_s,
      deadline: deadline.iso8601(3),
      selectedDateRangeId: selected_date_range_id&.to_s,
      closedAt: closed_at&.iso8601(3),
      status: status,
      dateRangeIds: date_range_ids,
      createdAt: created_at.iso8601(3),
      updatedAt: updated_at.iso8601(3)
    }
  end

  class << self
    extend T::Sig
    include Result::Methods

    sig { params(id: T.any(String, UUID)).returns(T.nilable(DatePoll)) }
    def find(id)
      dataset.where(id: id).first
    end

    sig { params(workspace_id: T.any(String, UUID), since: Time).returns(T::Array[DatePoll]) }
    def changed_since(workspace_id, since)
      dataset
        .join(:events, id: :event_id)
        .where(Sequel[:events][:workspace_id] => workspace_id)
        .where(Sequel.lit("date_polls.updated_at > ?", since))
        .select_all(:date_polls)
        .all
    end

    sig { params(event_id: T.any(String, UUID)).returns(T.nilable(DatePoll)) }
    def find_by_event(event_id)
      dataset.where(event_id: event_id).first
    end

    sig { params(event_ids: T::Array[String]).returns(T::Hash[String, DatePoll]) }
    def for_event_ids(event_ids)
      return {} if event_ids.empty?

      dataset.where(event_id: event_ids).each_with_object({}) { |p, h| h[p.event_id.to_s] = p }
    end

    sig { params(event_id: T.any(String, UUID)).returns(Result[DatePoll, ServiceError]) }
    def find_by_event_result(event_id)
      poll = find_by_event(event_id)
      if poll
        T.cast(Success(poll), Result[DatePoll, ServiceError])
      else
        T.cast(Failure(ServiceError.not_found("No date poll found for this event")), Result[DatePoll, ServiceError])
      end
    end

    sig { params(poll: DatePoll).returns(Result[DatePoll, ServiceError]) }
    def validate_open(poll)
      if poll.open?
        T.cast(Success(poll), Result[DatePoll, ServiceError])
      else
        T.cast(Failure(ServiceError.validation("Poll is not open for changes")), Result[DatePoll, ServiceError])
      end
    end

    private

    sig { returns(Sequel::Dataset) }
    def dataset
      DB[:date_polls].with_row_proc(method(:from_row))
    end

    sig { params(row: T::Hash[Symbol, T.untyped]).returns(DatePoll) }
    def from_row(row)
      DatePoll.new(
        id: UUID.new(row[:id]),
        event_id: UUID.new(row[:event_id]),
        deadline: row[:deadline],
        selected_date_range_id: row[:selected_date_range_id] ? UUID.new(row[:selected_date_range_id]) : nil,
        closed_at: row[:closed_at],
        created_at: row[:created_at],
        updated_at: row[:updated_at]
      )
    end
  end
end
