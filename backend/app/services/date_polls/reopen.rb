# frozen_string_literal: true

module DatePolls
  # Service to reopen a resolved date poll with a new deadline.
  module Reopen
    class << self
      include Dry::Monads[:result]

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
        deleted_rsvp_ids = []

        DB.transaction do
          # Delete all RSVPs for this event
          rsvp_ids = Rsvp.ids_for_event(event.id)
          DeletedItems.bulk_insert(event.workspace_id, "rsvp", rsvp_ids, deleted_by: membership.user_id)
          rsvp_ids.each do |rid|
            Broadcaster.object_deleted("rsvp", rid, workspace_id: event.workspace_id)
          end
          DB[:rsvps].where(event_id: event.id).delete
          deleted_rsvp_ids = rsvp_ids.map(&:to_s)

          DB[:date_polls].where(id: poll.id).update(
            deadline: deadline,
            selected_date_range_id: nil,
            closed_at: nil
          )

          DB[:events].where(id: event.id).update(
            start_date: nil,
            end_date: nil
          )

          Broadcaster.object_changed("date_poll", poll.id, workspace_id: event.workspace_id)
          Broadcaster.object_changed("event", event.id, workspace_id: event.workspace_id)
        end

        APP_LOGGER.info { "[DatePolls::Reopen] Poll #{poll.id} reopened on event #{event.id}" }

        pool = PoolSerializer.new(membership: membership)
        pool.add(:event, [Event.find(event.id)])
        pool.add(:date_poll, [DatePoll.find(poll.id)])

        deleted = deleted_rsvp_ids.map { |rid| { objectType: "rsvp", id: rid } }
        Success({ objects: pool.to_a, deleted: deleted })
      end
    end
  end
end
