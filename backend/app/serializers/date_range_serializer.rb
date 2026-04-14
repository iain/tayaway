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

    def policy_context(_range) = {}
    def policy_context_batch(_ranges) = {}
  end
end
