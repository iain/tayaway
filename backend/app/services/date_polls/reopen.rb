# typed: true
# frozen_string_literal: true

module DatePolls
  # Service to reopen a resolved date poll with a new deadline.
  module Reopen
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          deadline: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, current_user_id:, deadline:)
        Event.find_result(event_id)
             .bind { |event| Event.authorize_owner(event, current_user_id) }
             .bind { |event| DatePoll.find_by_event_result(event.id).fmap { |poll| [event, poll] } }
             .bind { |(event, poll)| validate_resolved(event, poll) }
             .bind { |(event, poll)| validate_deadline(deadline, event, poll) }
             .bind { |(event, poll, parsed_deadline)| reopen_poll(event, poll, parsed_deadline) }
      end

      private

      sig { params(event: Event, poll: DatePoll).returns(Result[T::Array[T.untyped], ServiceError]) }
      def validate_resolved(event, poll)
        unless poll.closed_at
          return T.cast(Failure(ServiceError.validation("Poll is not resolved")), Result[T::Array[T.untyped], ServiceError])
        end

        T.cast(Success([event, poll]), Result[T::Array[T.untyped], ServiceError])
      end

      sig do
        params(deadline: T.nilable(String), event: Event, poll: DatePoll)
          .returns(Result[T::Array[T.untyped], ServiceError])
      end
      def validate_deadline(deadline, event, poll)
        if deadline.nil? || deadline.empty?
          return T.cast(Failure(ServiceError.validation("Deadline is required")), Result[T::Array[T.untyped], ServiceError])
        end

        begin
          parsed = Time.parse(deadline)
        rescue ArgumentError
          return T.cast(Failure(ServiceError.validation("Invalid deadline format")), Result[T::Array[T.untyped], ServiceError])
        end

        if parsed <= Time.now
          return T.cast(Failure(ServiceError.validation("Deadline must be in the future")), Result[T::Array[T.untyped], ServiceError])
        end

        T.cast(Success([event, poll, parsed]), Result[T::Array[T.untyped], ServiceError])
      end

      sig do
        params(event: Event, poll: DatePoll, deadline: Time)
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def reopen_poll(event, poll, deadline)
        deleted_rsvp_ids = T.let([], T::Array[String])

        DB.transaction do
          # Delete all RSVPs for this event
          rsvp_ids = Rsvp.ids_for_event(event.id)
          rsvp_ids.each do |rid|
            DB[:deleted_items].insert(workspace_id: event.workspace_id, object_type: "rsvp", object_id: rid)
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

        pool = PoolSerializer.new(workspace_id: event.workspace_id)
        pool.add_event(T.must(Event.find(event.id)))
        pool.add_date_poll(T.must(DatePoll.find(poll.id)))

        deleted = deleted_rsvp_ids.map { |rid| { objectType: "rsvp", id: rid } }
        T.cast(Success({ objects: pool.to_a, deleted: deleted }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
