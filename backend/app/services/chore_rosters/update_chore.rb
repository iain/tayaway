# typed: true
# frozen_string_literal: true

module ChoreRosters
  # Service to update a chore (name, people_per_day, position).
  module UpdateChore
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          chore_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID),
          name: T.nilable(String),
          people_per_day: T.nilable(Integer),
          position: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(chore_id:, workspace_id:, name: nil, people_per_day: nil, position: nil)
        Chore.find_result(chore_id)
             .bind { |chore| validate_and_update(chore, workspace_id, name, people_per_day, position) }
      end

      private

      sig do
        params(
          chore: Chore,
          workspace_id: T.any(String, UUID),
          name: T.nilable(String),
          people_per_day: T.nilable(Integer),
          position: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def validate_and_update(chore, workspace_id, name, people_per_day, position)
        updates = {}

        if name
          if name.empty?
            return T.cast(
              Failure(ServiceError.validation("Name cannot be empty")),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
          end
          if name.length > ValidationLimits::SHORT_STRING
            return T.cast(
              Failure(ServiceError.validation("Name is too long (maximum #{ValidationLimits::SHORT_STRING} characters)")),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
          end
          updates[:name] = name
        end

        if people_per_day
          if people_per_day < 1 || people_per_day > ValidationLimits::PEOPLE_PER_DAY_MAX
            return T.cast(
              Failure(ServiceError.validation("People per day must be between 1 and #{ValidationLimits::PEOPLE_PER_DAY_MAX}")),
              Result[T::Hash[Symbol, T.untyped], ServiceError]
            )
          end
          updates[:people_per_day] = people_per_day
        end

        updates[:position] = position if position

        if updates.empty?
          return T.cast(
            Failure(ServiceError.validation("No changes provided")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        DB.transaction do
          DB[:chores].where(id: chore.id).update(updates)
          Broadcaster.object_changed("chore", chore.id, workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)
        updated_chore = T.must(Chore.find(chore.id))
        pool.add_chore(updated_chore)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
