# frozen_string_literal: true

module DatePolls
  # Service to add a date range to a date poll.
  module AddDateRange
    class << self
      include Dry::Monads[:result]

      def call(event_id:, membership:, start_date:, end_date:, id: nil)
        Event.find_result(event_id)
             .bind { |event| authorize(event, membership) }
             .bind { |event| DatePoll.find_by_event_result(event.id).fmap { |poll| [event, poll] } }
             .bind { |(event, poll)| DatePoll.validate_open(poll).fmap { |_| [event, poll] } }
             .bind { |(event, poll)| parse_dates(start_date, end_date, event, poll) }
             .bind { |(event, poll, date_input)| insert_date_range(event, poll, date_input, id) }
      end

      private

      def authorize(event, membership)
        EventPolicy.new(event, membership: membership)
                   .create_poll
                   .bind { Success(event) }
                   .or { |reason| Failure(ServiceError.forbidden(reason.to_s)) }
      end

      def parse_dates(start_date, end_date, event, poll)
        DateRangeInput.parse_strings(start_date, end_date).fmap { |date_input| [event, poll, date_input] }
      end

      def insert_date_range(event, poll, date_input, id)
        # Idempotent replay: if client provided an ID and it already exists, return current state
        if id
          existing = DateRange.find(id)
          if existing
            pool = PoolSerializer.new(workspace_id: event.workspace_id)
            pool.add_date_poll(DatePoll.find(poll.id))
            pool.add_date_range(existing)
            return Success({ objects: pool.to_a })
          end
        end

        dr_id = id || SecureRandom.uuid
        now = Time.now

        begin
          DB.transaction do
            DB[:date_ranges].insert(
              id: dr_id,
              date_poll_id: poll.id,
              start_date: date_input.start_date,
              end_date: date_input.end_date,
              created_at: now,
              updated_at: now
            )

            Broadcaster.object_changed("date_range", dr_id, workspace_id: event.workspace_id)
          end
        rescue Sequel::UniqueConstraintViolation
          dr_id = id
        end

        pool = PoolSerializer.new(workspace_id: event.workspace_id)
        pool.add_date_poll(DatePoll.find(poll.id))
        pool.add_date_range(DateRange.find(dr_id))
        Success({ objects: pool.to_a })
      end
    end
  end
end
