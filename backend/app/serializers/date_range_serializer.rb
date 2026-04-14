# frozen_string_literal: true

class DateRangeSerializer
  class << self
    def serialize_batch(ranges, pool:)
      ranges.map do |range|
        {
          id: range.id.to_s,
          objectType: "dateRange",
          datePollId: range.date_poll_id.to_s,
          startDate: range.start_date.iso8601,
          endDate: range.end_date.iso8601,
          updatedAt: range.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(range)
      policy_context_batch([range])[range.id.to_s] || {}
    end

    def policy_context_batch(ranges)
      return {} if ranges.empty?

      poll_ids = ranges.map { |r| r.date_poll_id.to_s }.uniq
      event_id_by_poll = DB[:date_polls].where(id: poll_ids).select_hash(:id, :event_id)
      event_ids = event_id_by_poll.values.map(&:to_s).uniq
      events_by_id = Event.for_ids(event_ids).each_with_object({}) { |e, h| h[e.id.to_s] = e }

      ranges.each_with_object({}) do |range, h|
        event_id = event_id_by_poll[range.date_poll_id.to_s]&.to_s
        h[range.id.to_s] = { event: events_by_id[event_id] }
      end
    end
  end
end
