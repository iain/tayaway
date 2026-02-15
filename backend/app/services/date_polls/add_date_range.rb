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
          end_date: T.nilable(String),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, current_user_id:, start_date:, end_date:, id: nil)
        Event.find_result(event_id)
             .bind { |event| Event.authorize_owner(event, current_user_id) }
             .bind { |event| DatePoll.find_by_event_result(event.id).fmap { |poll| [event, poll] } }
             .bind { |(event, poll)| DatePoll.validate_open(poll).fmap { |_| [event, poll] } }
             .bind { |(event, poll)| parse_dates(start_date, end_date, event, poll) }
             .bind { |(event, poll, date_input)| insert_date_range(event, poll, date_input, id) }
      end

      private

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
        params(event: Event, poll: DatePoll, date_input: DateRangeInput, id: T.nilable(String))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def insert_date_range(event, poll, date_input, id)
        # Idempotent replay: if client provided an ID and it already exists, return current state
        if id
          existing = DateRange.find(id)
          if existing
            pool = PoolSerializer.new(workspace_id: event.workspace_id)
            pool.add_date_poll(T.must(DatePoll.find(poll.id)))
            pool.add_date_range(existing)
            return T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
          end
        end

        dr_id = id || SecureRandom.uuid
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

          Broadcaster.object_changed("date_range", dr_id, workspace_id: event.workspace_id)
        end

        pool = PoolSerializer.new(workspace_id: event.workspace_id)
        pool.add_date_poll(T.must(DatePoll.find(poll.id)))
        pool.add_date_range(T.must(DateRange.find(dr_id)))
        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
