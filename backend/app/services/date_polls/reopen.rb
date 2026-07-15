# frozen_string_literal: true

module DatePolls
  # Service to reopen a resolved date poll with a new deadline.
  module Reopen
    class << self
      def call(event_id:, membership:, deadline:)
        Auditable.around(
          service: "DatePolls::Reopen",
          actor: membership,
          subject_type: "date_poll"
        ) do
          Success()
            .bind { Event.find_result(event_id) }
            .bind { |event| DatePoll.find_by_event_result(event.id).fmap { |poll| [event, poll] } }
            .bind { |(event, poll)| DatePollPolicy.enforce(:reopen, poll, membership: membership, event: event).fmap { |_| [event, poll] } }
            .bind { |(event, poll)| validate_resolved(event, poll) }
            .bind { |(event, poll)| validate_deadline(deadline, event, poll) }
            .bind { |(event, poll, parsed_deadline)| reopen_poll(event, poll, parsed_deadline, membership) }
        end
      end

      private

      def validate_resolved(event, poll)
        unless poll.closed_at
          return Failure(ServiceError.validation("Poll is not resolved"))
        end

        Success([event, poll])
      end

      def validate_deadline(deadline, event, poll)
        if deadline.nil? || deadline.empty?
          return Failure(ServiceError.validation("Deadline is required"))
        end

        begin
          parsed = Time.parse(deadline)
        rescue ArgumentError
          return Failure(ServiceError.validation("Invalid deadline format"))
        end

        if parsed <= Time.now
          return Failure(ServiceError.validation("Deadline must be in the future"))
        end

        Success([event, poll, parsed])
      end

      def reopen_poll(event, poll, deadline, membership)
        DB.transaction do
          # A reopen keeps the people and clears the answers — every row
          # (member and guest alike) reverts to pending (doc/attendances.md).
          attendance_ids = Attendance.ids_for_event(event.id)
          if attendance_ids.any?
            DB[:attendances].where(id: attendance_ids).update(status: "pending", days: nil, updated_at: Time.now)
            attendance_ids.each { |aid| Broadcaster.object_changed("attendance", aid) }
          end

          DB[:date_polls].where(id: poll.id).update(
            deadline: deadline,
            selected_date_range_id: nil,
            closed_at: nil
          )

          DB[:events].where(id: event.id).update(
            start_date: nil,
            end_date: nil
          )

          Broadcaster.object_changed("date_poll", poll.id)
          Broadcaster.object_changed("event", event.id)
        end

        APP_LOGGER.info { "[DatePolls::Reopen] Poll #{poll.id} reopened on event #{event.id}" }

        pool = PoolSerializer.new(membership: membership)
        pool.add(:event, [Event.find(event.id)])
        pool.add(:date_poll, [DatePoll.find(poll.id)])

        Success({ objects: pool.to_a })
      end
    end
  end
end
