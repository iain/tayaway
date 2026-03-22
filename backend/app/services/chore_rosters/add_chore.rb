# typed: true
# frozen_string_literal: true

module ChoreRosters
  # Service to add a chore to a roster.
  module AddChore
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          roster_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID),
          name: T.nilable(String),
          people_per_day: T.nilable(Integer),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(roster_id:, workspace_id:, name:, people_per_day:, id: nil)
        validate(name, people_per_day)
          .bind { |valid| create_chore(roster_id, workspace_id, valid, id) }
      end

      private

      sig do
        params(
          name: T.nilable(String),
          people_per_day: T.nilable(Integer)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def validate(name, people_per_day)
        if name.nil? || name.empty?
          return T.cast(
            Failure(ServiceError.validation("Name is required")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        if name.length > ValidationLimits::SHORT_STRING
          return T.cast(
            Failure(ServiceError.validation("Name is too long (maximum #{ValidationLimits::SHORT_STRING} characters)")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        ppd = people_per_day || 1
        if ppd < 1 || ppd > ValidationLimits::PEOPLE_PER_DAY_MAX
          return T.cast(
            Failure(ServiceError.validation("People per day must be between 1 and #{ValidationLimits::PEOPLE_PER_DAY_MAX}")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        T.cast(
          Success({ name: name, people_per_day: ppd }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end

      sig do
        params(
          roster_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID),
          valid: T::Hash[Symbol, T.untyped],
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_chore(roster_id, workspace_id, valid, id)
        # Idempotent replay
        if id
          existing = Chore.find(id)
          if existing
            pool = PoolSerializer.new(workspace_id: workspace_id)
            pool.add_chore(existing)
            return T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
          end
        end

        chore_id = id || SecureRandom.uuid
        now = Time.now
        position = Chore.max_position(roster_id) + 1.0

        DB.transaction do
          DB[:chores].insert(
            id: chore_id,
            chore_roster_id: roster_id,
            name: valid[:name],
            people_per_day: valid[:people_per_day],
            position: position,
            created_at: now,
            updated_at: now
          )
          Broadcaster.object_changed("chore", chore_id, workspace_id: workspace_id)
          Broadcaster.object_changed("chore_roster", roster_id, workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)
        chore = T.must(Chore.find(chore_id))
        pool.add_chore(chore)
        roster = T.must(ChoreRoster.find(roster_id))
        pool.add_chore_roster(roster)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
