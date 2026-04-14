# frozen_string_literal: true

class DatePollSerializer
  class << self
    def serialize_batch(polls, pool:)
      return [] if polls.empty?

      poll_ids = polls.map { |p| p.id.to_s }
      range_ids_by_poll = DateRange.ids_for_date_poll_ids(poll_ids)

      polls.map do |poll|
        {
          id: poll.id.to_s,
          objectType: "datePoll",
          eventId: poll.event_id.to_s,
          deadline: poll.deadline.iso8601(3),
          selectedDateRangeId: poll.selected_date_range_id&.to_s,
          closedAt: poll.closed_at&.iso8601(3),
          status: poll.status,
          dateRangeIds: range_ids_by_poll[poll.id.to_s] || [],
          createdAt: poll.created_at.iso8601(3),
          updatedAt: poll.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(poll)
      policy_context_batch([poll])[poll.id.to_s] || {}
    end

    def policy_context_batch(polls)
      return {} if polls.empty?

      event_ids = polls.map { |p| p.event_id.to_s }.uniq
      events_by_id = Event.for_ids(event_ids).each_with_object({}) { |e, h| h[e.id.to_s] = e }

      polls.each_with_object({}) do |poll, h|
        h[poll.id.to_s] = { event: events_by_id[poll.event_id.to_s] }
      end
    end
  end
end
