# frozen_string_literal: true

module DatePolls
  # Service to remove a date range from a date poll.
  module RemoveDateRange
    class << self
      include Dry::Monads[:result]

      def call(event_id:, membership:, date_range_id:)
        Event.find_result(event_id)
             .bind { |event| authorize(event, membership) }
             .bind { |event| DatePoll.find_by_event_result(event.id).fmap { |poll| [event, poll] } }
             .bind { |(event, poll)| DatePoll.validate_open(poll).fmap { |_| [event, poll] } }
             .bind { |(event, poll)| validate_date_range(event, poll, date_range_id) }
             .bind { |(event, poll, dr_id)| delete_date_range(event, poll, dr_id) }
      end

      private

      def authorize(event, membership)
        EventPolicy.new(event, membership: membership)
                   .edit
                   .bind { Success(event) }
                   .or { |reason| Failure(ServiceError.forbidden(reason.to_s)) }
      end

      def validate_date_range(event, poll, date_range_id)
        if date_range_id.nil? || date_range_id.empty?
          return Failure(ServiceError.validation("date_range_id is required"))
        end

        date_range = DateRange.find(date_range_id)
        unless date_range && date_range.date_poll_id == poll.id
          return Failure(ServiceError.validation("Date range does not belong to this poll"))
        end

        Success([event, poll, date_range_id])
      end

      def delete_date_range(event, poll, date_range_id)
        DB.transaction do
          DB[:deleted_items].insert(workspace_id: event.workspace_id, object_type: "dateRange", object_id: date_range_id)
          DB[:date_ranges].where(id: date_range_id).delete
          Broadcaster.object_deleted("date_range", date_range_id, workspace_id: event.workspace_id)
        end

        pool = PoolSerializer.new(workspace_id: event.workspace_id)
        pool.add_date_poll(DatePoll.find(poll.id))

        Success({ objects: pool.to_a, deleted: [{ objectType: "dateRange", id: date_range_id }] })
      end
    end
  end
end
