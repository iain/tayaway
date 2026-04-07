# frozen_string_literal: true

module ChoreRosters
  # Service to add a chore to a roster.
  module AddChore
    class << self
      include Dry::Monads[:result]

      def call(roster_id:, workspace_id:, name:, people_per_day:, id: nil)
        validate(name, people_per_day)
          .bind { |valid| create_chore(roster_id, workspace_id, valid, id) }
      end

      private

      def validate(name, people_per_day)
        if name.nil? || name.empty?
          return Failure(ServiceError.validation("Name is required"))
        end

        if name.length > ValidationLimits::SHORT_STRING
          return Failure(ServiceError.validation("Name is too long (maximum #{ValidationLimits::SHORT_STRING} characters)"))
        end

        ppd = people_per_day || 1
        if ppd < 1 || ppd > ValidationLimits::PEOPLE_PER_DAY_MAX
          return Failure(ServiceError.validation("People per day must be between 1 and #{ValidationLimits::PEOPLE_PER_DAY_MAX}"))
        end

        Success({ name: name, people_per_day: ppd })
      end

      def create_chore(roster_id, workspace_id, valid, id)
        # Idempotent replay
        if id
          existing = Chore.find(id)
          if existing
            pool = PoolSerializer.new(workspace_id: workspace_id)
            pool.add_chore(existing)
            return Success({ objects: pool.to_a })
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
        chore = Chore.find(chore_id)
        pool.add_chore(chore)
        roster = ChoreRoster.find(roster_id)
        pool.add_chore_roster(roster)

        Success({ objects: pool.to_a })
      end
    end
  end
end
