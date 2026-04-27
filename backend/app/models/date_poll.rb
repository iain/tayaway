# frozen_string_literal: true

# Read-only date poll model.
class DatePoll < Data.define(:id, :event_id, :deadline, :selected_date_range_id, :closed_at, :created_at, :updated_at)
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

  class << self
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
      new(
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
