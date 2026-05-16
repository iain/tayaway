# frozen_string_literal: true

module DatePolls
  # Service to remove a date range from a date poll.
  module RemoveDateRange
    class << self
      def call(event_id:, membership:, date_range_id:)
        Auditable.around(
          service: "DatePolls::RemoveDateRange",
          actor: membership,
          subject_type: "date_range",
          subject_id: date_range_id
        ) do
          Success()
            .bind { Event.find_result(event_id) }
            .bind { |event| DatePoll.find_by_event_result(event.id).fmap { |poll| [event, poll] } }
            .bind { |(event, poll)| DatePoll.validate_open(poll).fmap { |_| [event, poll] } }
            .bind { |(event, poll)| validate_date_range(event, poll, date_range_id) }
            .bind { |(event, poll, date_range)| DateRangePolicy.enforce(:delete, date_range, membership: membership, event: event).fmap { |_| [event, poll, date_range.id] } }
            .bind { |(event, poll, dr_id)| delete_date_range(event, poll, dr_id, membership) }
        end
      end

      private

      def validate_date_range(event, poll, date_range_id)
        if date_range_id.nil? || date_range_id.empty?
          return Failure(ServiceError.validation("date_range_id is required"))
        end

        date_range = DateRange.find(date_range_id)
        unless date_range && date_range.date_poll_id == poll.id
          return Failure(ServiceError.validation("Date range does not belong to this poll"))
        end

        Success([event, poll, date_range])
      end

      def delete_date_range(event, poll, date_range_id, membership)
        DB.transaction do
          DB[:deleted_items].insert(workspace_id: event.workspace_id, object_type: "dateRange", object_id: date_range_id)
          DB[:date_ranges].where(id: date_range_id).delete
          Broadcaster.object_deleted("date_range", date_range_id, topics: [Topic.workspace(event.workspace_id)])
        end

        pool = PoolSerializer.new(membership: membership)
        pool.add(:date_poll, [DatePoll.find(poll.id)])

        Success({ objects: pool.to_a, deleted: [{ objectType: "dateRange", id: date_range_id }] })
      end
    end
  end
end
