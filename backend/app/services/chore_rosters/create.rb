# frozen_string_literal: true

module ChoreRosters
  # Service to create a chore roster for an event.
  module Create
    class << self
      def call(event_id:, membership:, workspace_id:, id: nil)
        Auditable.around(
          service: "ChoreRosters::Create",
          actor: membership,
          subject_type: "chore_roster",
          subject_id: id,
          workspace_id: workspace_id
        ) do
          Success()
            .bind { find_event(event_id) }
            .bind { |event| EventPolicy.enforce(:create_chore_roster, event, membership: membership) }
            .bind { |event| check_event_dates(event) }
            .bind { |event| check_no_existing_roster(event, id) }
            .bind { |event| create_roster(event, membership, workspace_id, id) }
        end
      end

      private

      def find_event(event_id)
        Event.find_result(event_id)
      end

      def check_event_dates(event)
        if event.start_date && event.end_date
          Success(event)
        else
          Failure(ServiceError.validation("Event must have dates set before creating a chore roster"))
        end
      end

      def check_no_existing_roster(event, id)
        # Idempotent replay: if client provided an ID and it already exists, that's fine
        # but only if the event matches
        if id
          existing = ChoreRoster.find(id)
          return Success(event) if existing && existing.event_id.to_s == event.id.to_s
        end

        existing = ChoreRoster.find_by_event(event.id)
        if existing
          Failure(ServiceError.validation("A chore roster already exists for this event"))
        else
          Success(event)
        end
      end

      def create_roster(event, membership, workspace_id, id)
        # Idempotent replay — only skip creation if the existing roster matches this event
        if id
          existing = ChoreRoster.find(id)
          if existing && existing.event_id.to_s == event.id.to_s
            pool = PoolSerializer.new(membership: membership)
            pool.add(:chore_roster, [existing])
            return Success({ objects: pool.to_a })
          end
        end

        # If the provided ID already exists (different event), generate a new one
        roster_id = id && !ChoreRoster.find(id) ? id : SecureRandom.uuid
        now = Time.now

        DB.transaction do
          DB[:chore_rosters].insert(
            id: roster_id,
            event_id: event.id,
            user_id: membership.user_id,
            created_at: now,
            updated_at: now
          )
          Broadcaster.object_changed("chore_roster", roster_id)
        end

        pool = PoolSerializer.new(membership: membership)
        roster = ChoreRoster.find(roster_id)
        pool.add(:chore_roster, [roster])

        Success({ objects: pool.to_a })
      end
    end
  end
end
