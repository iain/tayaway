# typed: true
# frozen_string_literal: true

module DatePolls
  # Service to add a date range to a date poll.
  module AddDateRange
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          start_date: T.nilable(String),
          end_date: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, current_user_id:, start_date:, end_date:)
        find_event(event_id)
          .bind { |event| authorize_owner(event, current_user_id) }
          .bind { |event| find_poll(event) }
          .bind { |(event, poll)| validate_poll_open(event, poll) }
          .bind { |(event, poll)| parse_dates(start_date, end_date, event, poll) }
          .bind { |(event, poll, date_input)| insert_date_range(event, poll, date_input) }
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
        params(
          start_date: T.nilable(String),
          end_date: T.nilable(String),
          event: Event,
          poll: DatePoll
        ).returns(Result[T::Array[T.untyped], ServiceError])
      end
      def parse_dates(start_date, end_date, event, poll)
        T.cast(
          DateRangeInput.parse_strings(start_date, end_date).fmap { |date_input| [event, poll, date_input] },
          Result[T::Array[T.untyped], ServiceError]
        )
      end

      sig do
        params(event: Event, poll: DatePoll, date_input: DateRangeInput)
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def insert_date_range(event, poll, date_input)
        dr_id = SecureRandom.uuid
        now = Time.now

        DB.transaction do
          DB[:date_ranges].insert(
            id: dr_id,
            date_poll_id: poll.id,
            start_date: date_input.start_date,
            end_date: date_input.end_date,
            created_at: now,
            updated_at: now
          )

          DB[:date_polls].where(id: poll.id).update(updated_at: now)

          Broadcaster.object_changed("date_poll", poll.id, workspace_id: event.workspace_id)
        end

        pool = PoolSerializer.new
        pool.add_event(T.must(Event.find(event.id)))

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
