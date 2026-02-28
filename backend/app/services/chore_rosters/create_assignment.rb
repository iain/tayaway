# typed: true
# frozen_string_literal: true

module ChoreRosters
  # Service to pin an assignment (always pinned=true).
  module CreateAssignment
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          roster_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID),
          chore_id: T.nilable(String),
          user_id: T.nilable(String),
          date: T.nilable(String),
          note: T.nilable(String),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(roster_id:, workspace_id:, chore_id:, user_id:, date:, note: nil, id: nil)
        validate(chore_id, user_id, date)
          .bind { |valid| validate_chore_belongs(valid, roster_id) }
          .bind { |valid| validate_date_in_range(valid, roster_id) }
          .bind { |valid| create_assignment(valid, workspace_id, note, id) }
      end

      private

      sig do
        params(
          chore_id: T.nilable(String),
          user_id: T.nilable(String),
          date: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def validate(chore_id, user_id, date)
        if chore_id.nil? || chore_id.empty?
          return T.cast(
            Failure(ServiceError.validation("chore_id is required")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        if user_id.nil? || user_id.empty?
          return T.cast(
            Failure(ServiceError.validation("user_id is required")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        if date.nil? || date.empty?
          return T.cast(
            Failure(ServiceError.validation("date is required")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        T.cast(
          Success({ chore_id: chore_id, user_id: user_id, date: Date.parse(date) }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end

      sig do
        params(
          valid: T::Hash[Symbol, T.untyped],
          roster_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def validate_chore_belongs(valid, roster_id)
        chore = Chore.find(valid[:chore_id])
        if chore.nil? || chore.chore_roster_id.to_s != roster_id.to_s
          return T.cast(
            Failure(ServiceError.not_found("Chore not found in this roster")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        T.cast(Success(valid), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end

      sig do
        params(
          valid: T::Hash[Symbol, T.untyped],
          roster_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def validate_date_in_range(valid, roster_id)
        roster = ChoreRoster.find(roster_id)
        return T.cast(Failure(ServiceError.not_found("Roster not found")), Result[T::Hash[Symbol, T.untyped], ServiceError]) unless roster

        event = Event.find(roster.event_id)
        return T.cast(Failure(ServiceError.not_found("Event not found")), Result[T::Hash[Symbol, T.untyped], ServiceError]) unless event

        if event.start_date && event.end_date
          if valid[:date] < event.start_date || valid[:date] > event.end_date
            return T.cast(
              Failure(ServiceError.validation("Date must be within event date range")),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
          end
        end

        T.cast(Success(valid), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end

      sig do
        params(
          valid: T::Hash[Symbol, T.untyped],
          workspace_id: T.any(String, UUID),
          note: T.nilable(String),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_assignment(valid, workspace_id, note, id)
        # Idempotent replay
        if id
          existing = ChoreAssignment.find(id)
          if existing
            pool = PoolSerializer.new(workspace_id: workspace_id)
            pool.add_chore_assignment(existing)
            return T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
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

        pool = PoolSerializer.new(workspace_id: workspace_id)
        assignment = T.must(ChoreAssignment.find(assignment_id))
        pool.add_chore_assignment(assignment)
        chore = T.must(Chore.find(valid[:chore_id]))
        pool.add_chore(chore)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
