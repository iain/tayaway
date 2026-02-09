# typed: true
# frozen_string_literal: true

module DatePolls
  # Service to close a date poll by selecting a winning date range.
  module Close
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          selected_date_range_id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, current_user_id:, selected_date_range_id:)
        find_event(event_id)
          .bind { |event| authorize_owner(event, current_user_id) }
          .bind { |event| find_poll(event) }
          .bind { |(event, poll)| validate_not_resolved(event, poll) }
          .bind { |(event, poll)| validate_date_range(event, poll, selected_date_range_id) }
          .bind { |(event, poll, dr_id)| close_poll(event, poll, dr_id) }
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
      def validate_not_resolved(event, poll)
        if poll.closed_at
          T.cast(Failure(ServiceError.validation("Poll is already resolved")), Result[T::Array[T.untyped], ServiceError])
        else
          T.cast(Success([event, poll]), Result[T::Array[T.untyped], ServiceError])
        end
      end

      sig do
        params(
          event: Event,
          poll: DatePoll,
          selected_date_range_id: T.nilable(String)
        ).returns(Result[T::Array[T.untyped], ServiceError])
      end
      def validate_date_range(event, poll, selected_date_range_id)
        if selected_date_range_id.nil? || selected_date_range_id.empty?
          return T.cast(
            Failure(ServiceError.validation("selected_date_range_id is required")),
            Result[T::Array[T.untyped], ServiceError]
          )
        end

        date_range = DateRange.find(selected_date_range_id)
        unless date_range && date_range.date_poll_id == poll.id
          return T.cast(
            Failure(ServiceError.validation("Date range does not belong to this poll")),
            Result[T::Array[T.untyped], ServiceError]
          )
        end

        T.cast(Success([event, poll, selected_date_range_id]), Result[T::Array[T.untyped], ServiceError])
      end

      sig do
        params(event: Event, poll: DatePoll, selected_date_range_id: String)
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def close_poll(event, poll, selected_date_range_id)
        DB.transaction do
          DB[:date_polls].where(id: poll.id).update(
            selected_date_range_id: selected_date_range_id,
            closed_at: Time.now
          )

          Broadcaster.object_changed("date_poll", poll.id, workspace_id: event.workspace_id)
        end

        pool = PoolSerializer.new
        pool.add_event(T.must(Event.find(event.id)))

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
