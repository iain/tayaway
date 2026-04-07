# frozen_string_literal: true

# Read-only date poll model.
class DatePoll
  attr_reader :id, :event_id, :deadline, :selected_date_range_id, :closed_at, :created_at, :updated_at

  def initialize(
    id:,
    event_id:,
    deadline:,
    selected_date_range_id:,
    closed_at:,
    created_at:,
    updated_at:
  )
    @id = id
    @event_id = event_id
    @deadline = deadline
    @selected_date_range_id = selected_date_range_id
    @closed_at = closed_at
    @created_at = created_at
    @updated_at = updated_at
  end

  def status
    if closed_at
      "resolved"
    elsif deadline < Time.now
      "expired"
    else
      "open"
    end
  end

  def open?
    status == "open"
  end

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
    include Dry::Monads[:result]

    def find(id)
      dataset.where(id: id).first
    end

    def changed_since(workspace_id, since)
      dataset
        .join(:events, id: :event_id)
        .where(Sequel[:events][:workspace_id] => workspace_id)
        .where(Sequel.lit("date_polls.updated_at > ?", since))
        .select_all(:date_polls)
        .all
    end

    def find_by_event(event_id)
      dataset.where(event_id: event_id).first
    end

    def for_event_ids(event_ids)
      return {} if event_ids.empty?

      dataset.where(event_id: event_ids).each_with_object({}) { |p, h| h[p.event_id.to_s] = p }
    end

    def find_by_event_result(event_id)
      poll = find_by_event(event_id)
      if poll
        Success(poll)
      else
        Failure(ServiceError.not_found("No date poll found for this event"))
      end
    end

    def validate_open(poll)
      if poll.open?
        Success(poll)
      else
        Failure(ServiceError.validation("Poll is not open for changes"))
      end
    end

    private

    def dataset
      DB[:date_polls].with_row_proc(method(:from_row))
    end

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
