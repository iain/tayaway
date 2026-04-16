# frozen_string_literal: true

module ChoreRosters
  # Service to pin an assignment (always pinned=true).
  module CreateAssignment
    class << self
      include Dry::Monads[:result]

      def call(roster_id:, workspace_id:, membership:, chore_id:, user_id:, date:, note: nil, id: nil)
        validate(chore_id, user_id, date)
          .bind { |valid| enforce_policy(roster_id, membership, valid) }
          .bind { |valid| validate_chore_belongs(valid, roster_id) }
          .bind { |valid| validate_date_in_range(valid, roster_id) }
          .bind { |valid| create_assignment(valid, workspace_id, note, id, membership) }
      end

      private

      def validate(chore_id, user_id, date)
        if chore_id.nil? || chore_id.empty?
          return Failure(ServiceError.validation("chore_id is required"))
        end

        if user_id.nil? || user_id.empty?
          return Failure(ServiceError.validation("user_id is required"))
        end

        if date.nil? || date.empty?
          return Failure(ServiceError.validation("date is required"))
        end

        Success({ chore_id: chore_id, user_id: user_id, date: Date.parse(date) })
      end

      def enforce_policy(roster_id, membership, valid)
        roster = ChoreRoster.find(roster_id)
        return Failure(ServiceError.not_found("Roster not found")) unless roster

        ChoreRosterPolicy.enforce(:edit, roster, membership: membership)
                         .fmap { valid }
      end

      def validate_chore_belongs(valid, roster_id)
        chore = Chore.find(valid[:chore_id])
        if chore.nil? || chore.chore_roster_id.to_s != roster_id.to_s
          return Failure(ServiceError.not_found("Chore not found in this roster"))
        end

        Success(valid)
      end

      def validate_date_in_range(valid, roster_id)
        roster = ChoreRoster.find(roster_id)
        return Failure(ServiceError.not_found("Roster not found")) unless roster

        event = Event.find(roster.event_id)
        return Failure(ServiceError.not_found("Event not found")) unless event

        if event.start_date && event.end_date
          if valid[:date] < event.start_date || valid[:date] > event.end_date
            return Failure(ServiceError.validation("Date must be within event date range"))
          end
        end

        Success(valid)
      end

      def create_assignment(valid, workspace_id, note, id, membership)
        # Idempotent replay
        if id
          existing = ChoreAssignment.find(id)
          if existing
            pool = PoolSerializer.new(membership: membership)
            pool.add(:chore_assignment, [existing])
            return Success({ objects: pool.to_a })
          end
        end

        assignment_id = id || SecureRandom.uuid
        now = Time.now

        DB.transaction do
          DB[:chore_assignments].insert(
            id: assignment_id,
            chore_id: valid[:chore_id],
            user_id: valid[:user_id],
            date: valid[:date],
            pinned: true,
            note: note,
            created_at: now,
            updated_at: now
          )
          Broadcaster.object_changed("chore_assignment", assignment_id, workspace_id: workspace_id)
          # Update parent chore so clients see new assignment_ids
          Broadcaster.object_changed("chore", valid[:chore_id], workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(membership: membership)
        assignment = ChoreAssignment.find(assignment_id)
        pool.add(:chore_assignment, [assignment])
        chore = Chore.find(valid[:chore_id])
        pool.add(:chore, [chore])

        Success({ objects: pool.to_a })
      end
    end
  end
end
