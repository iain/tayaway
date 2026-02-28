# typed: true
# frozen_string_literal: true

module ChoreRosters
  # Service to create a chore roster for an event.
  module Create
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, user_id:, workspace_id:, id: nil)
        find_event(event_id)
          .bind { |event| check_event_dates(event) }
          .bind { |event| check_no_existing_roster(event, id) }
          .bind { |event| create_roster(event, user_id, workspace_id, id) }
      end

      private

      sig { params(event_id: T.any(String, UUID)).returns(Result[Event, ServiceError]) }
      def find_event(event_id)
        Event.find_result(event_id)
      end

      sig { params(event: Event).returns(Result[Event, ServiceError]) }
      def check_event_dates(event)
        if event.start_date && event.end_date
          T.cast(Success(event), Result[Event, ServiceError])
        else
          T.cast(
            Failure(ServiceError.validation("Event must have dates set before creating a chore roster")),
            Result[Event, ServiceError]
          )
        end
      end

      sig { params(event: Event, id: T.nilable(String)).returns(Result[Event, ServiceError]) }
      def check_no_existing_roster(event, id)
        # Idempotent replay: if client provided an ID and it already exists, that's fine
        # but only if the event matches
        if id
          existing = ChoreRoster.find(id)
          return T.cast(Success(event), Result[Event, ServiceError]) if existing && existing.event_id.to_s == event.id.to_s
        end

        existing = ChoreRoster.find_by_event(event.id)
        if existing
          T.cast(
            Failure(ServiceError.validation("A chore roster already exists for this event")),
            Result[Event, ServiceError]
          )
        else
          T.cast(Success(event), Result[Event, ServiceError])
        end
      end

      sig do
        params(
          event: Event,
          user_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_roster(event, user_id, workspace_id, id)
        # Idempotent replay — only skip creation if the existing roster matches this event
        if id
          existing = ChoreRoster.find(id)
          if existing && existing.event_id.to_s == event.id.to_s
            pool = PoolSerializer.new(workspace_id: workspace_id)
            pool.add_chore_roster(existing)
            return T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
          end
        end

        # If the provided ID already exists (different event), generate a new one
        roster_id = id && !ChoreRoster.find(id) ? id : SecureRandom.uuid
        now = Time.now

        DB.transaction do
          DB[:chore_rosters].insert(
            id: roster_id,
            event_id: event.id,
            user_id: user_id,
            created_at: now,
            updated_at: now
          )
          Broadcaster.object_changed("chore_roster", roster_id, workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)
        roster = T.must(ChoreRoster.find(roster_id))
        pool.add_chore_roster(roster)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
