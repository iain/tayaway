# typed: true
# frozen_string_literal: true

module DatePolls
  # Service to create a date poll for an event.
  module Create
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
             .bind { |event| EventPolicy.new(event: event, user_id: current_user_id.to_s).authorize!(:create_poll, value: event) }
             .bind { |event| validate_no_existing_poll(event) }
             .bind { |event| validate_deadline(deadline, event) }
             .bind { |(event, parsed_deadline)| create_poll(event, parsed_deadline, current_user_id) }
      end

      private

      sig { params(event: Event).returns(Result[Event, ServiceError]) }
      def validate_no_existing_poll(event)
        existing = DatePoll.find_by_event(event.id)
        if existing
          T.cast(Failure(ServiceError.conflict("A date poll already exists for this event")), Result[Event, ServiceError])
        else
          T.cast(Success(event), Result[Event, ServiceError])
        end
      end

      sig { params(deadline: T.nilable(String), event: Event).returns(Result[T::Array[T.untyped], ServiceError]) }
      def validate_deadline(deadline, event)
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

        T.cast(Success([event, parsed]), Result[T::Array[T.untyped], ServiceError])
      end

      sig { params(event: Event, deadline: Time, current_user_id: T.any(String, UUID)).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def create_poll(event, deadline, current_user_id)
        poll_id = SecureRandom.uuid
        now = Time.now

        DB.transaction do
          DB[:date_polls].insert(
            id: poll_id,
            event_id: event.id,
            deadline: deadline,
            created_at: now,
            updated_at: now
          )

          Broadcaster.object_changed("date_poll", poll_id, workspace_id: event.workspace_id)
        end

        pool = PoolSerializer.new(workspace_id: event.workspace_id, user_id: current_user_id.to_s)
        pool.add_event(T.must(Event.find(event.id)))
        pool.add_date_poll(T.must(DatePoll.find(poll_id)))
        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
