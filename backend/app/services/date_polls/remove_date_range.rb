# typed: true
# frozen_string_literal: true

module DatePolls
  # Service to remove a date range from a date poll.
  module RemoveDateRange
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          date_range_id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, current_user_id:, date_range_id:)
        find_event(event_id)
          .bind { |event| authorize_owner(event, current_user_id) }
          .bind { |event| find_poll(event) }
          .bind { |(event, poll)| validate_poll_open(event, poll) }
          .bind { |(event, poll)| validate_date_range(event, poll, date_range_id) }
          .bind { |(event, poll, dr_id)| delete_date_range(event, poll, dr_id) }
      end

      private

      sig { params(event_id: T.any(String, UUID)).returns(Result[Event, ServiceError]) }
      def find_event(event_id)
        event = Event.find(event_id)
        if event
          T.cast(Success(event), Result[Event, ServiceError])
        else
          T.cast(Failure(ServiceError.not_found("Event not found")), Result[Event, ServiceError])
        end
      end

      sig { params(event: Event, current_user_id: T.any(String, UUID)).returns(Result[Event, ServiceError]) }
      def authorize_owner(event, current_user_id)
        if event.user_id == current_user_id
          T.cast(Success(event), Result[Event, ServiceError])
        else
          T.cast(Failure(ServiceError.forbidden("Access denied")), Result[Event, ServiceError])
        end
      end

      sig { params(event: Event).returns(Result[T::Array[T.untyped], ServiceError]) }
      def find_poll(event)
        poll = DatePoll.find_by_event(event.id)
        if poll
          T.cast(Success([event, poll]), Result[T::Array[T.untyped], ServiceError])
        else
          T.cast(Failure(ServiceError.not_found("No date poll found for this event")), Result[T::Array[T.untyped], ServiceError])
        end
      end

      sig { params(event: Event, poll: DatePoll).returns(Result[T::Array[T.untyped], ServiceError]) }
      def validate_poll_open(event, poll)
        if poll.open?
          T.cast(Success([event, poll]), Result[T::Array[T.untyped], ServiceError])
        else
          T.cast(Failure(ServiceError.validation("Poll is not open for changes")), Result[T::Array[T.untyped], ServiceError])
        end
      end

      sig do
        params(event: Event, poll: DatePoll, date_range_id: T.nilable(String))
          .returns(Result[T::Array[T.untyped], ServiceError])
      end
      def validate_date_range(event, poll, date_range_id)
        if date_range_id.nil? || date_range_id.empty?
          return T.cast(
            Failure(ServiceError.validation("date_range_id is required")),
            Result[T::Array[T.untyped], ServiceError]
          )
        end

        date_range = DateRange.find(date_range_id)
        unless date_range && date_range.date_poll_id == poll.id
          return T.cast(
            Failure(ServiceError.validation("Date range does not belong to this poll")),
            Result[T::Array[T.untyped], ServiceError]
          )
        end

        T.cast(Success([event, poll, date_range_id]), Result[T::Array[T.untyped], ServiceError])
      end

      sig do
        params(event: Event, poll: DatePoll, date_range_id: String)
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def delete_date_range(event, poll, date_range_id)
        DB.transaction do
          DB[:deleted_items].insert(workspace_id: event.workspace_id, object_type: "dateRange", object_id: date_range_id)
          DB[:date_ranges].where(id: date_range_id).delete
          Broadcaster.object_deleted("date_range", date_range_id, workspace_id: event.workspace_id)
        end

        pool = PoolSerializer.new
        pool.add_event(T.must(Event.find(event.id)))

        T.cast(
          Success({ objects: pool.to_a, deleted: [{ objectType: "dateRange", id: date_range_id }] }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end
    end
  end
end
