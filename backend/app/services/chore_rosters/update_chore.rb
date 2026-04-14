# frozen_string_literal: true

module ChoreRosters
  # Service to update a chore (name, people_per_day, position).
  module UpdateChore
    class << self
      include Dry::Monads[:result]

      def call(chore_id:, workspace_id:, membership:, name: nil, people_per_day: nil, position: nil)
        Chore.find_result(chore_id)
             .bind { |chore| ChorePolicy.enforce(:edit, chore, membership: membership) }
             .bind { |chore| validate_and_update(chore, workspace_id, name, people_per_day, position, membership) }
      end

      private

      def validate_and_update(chore, workspace_id, name, people_per_day, position, membership)
        updates = {}

        if name
          if name.empty?
            return Failure(ServiceError.validation("Name cannot be empty"))
          end
          if name.length > ValidationLimits::SHORT_STRING
            return Failure(ServiceError.validation("Name is too long (maximum #{ValidationLimits::SHORT_STRING} characters)"))
          end
          updates[:name] = name
        end

        if people_per_day
          if people_per_day < 1 || people_per_day > ValidationLimits::PEOPLE_PER_DAY_MAX
            return Failure(ServiceError.validation("People per day must be between 1 and #{ValidationLimits::PEOPLE_PER_DAY_MAX}"))
          end
          updates[:people_per_day] = people_per_day
        end

        updates[:position] = position if position

        if updates.empty?
          return Failure(ServiceError.validation("No changes provided"))
        end

        DB.transaction do
          DB[:chores].where(id: chore.id).update(updates)
          Broadcaster.object_changed("chore", chore.id, workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(membership: membership)
        updated_chore = Chore.find(chore.id)
        pool.add(:chore, [updated_chore])

        Success({ objects: pool.to_a })
      end
    end
  end
end
