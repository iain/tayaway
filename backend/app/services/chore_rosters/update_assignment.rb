# typed: true
# frozen_string_literal: true

module ChoreRosters
  # Service to update a chore assignment (note, user_id).
  module UpdateAssignment
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          assignment_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID),
          note: T.nilable(String),
          user_id: T.nilable(String),
          pinned: T.nilable(T::Boolean)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(assignment_id:, workspace_id:, note: nil, user_id: nil, pinned: nil)
        ChoreAssignment.find_result(assignment_id)
                       .bind { |assignment| update(assignment, workspace_id, note, user_id, pinned) }
      end

      private

      sig do
        params(
          assignment: ChoreAssignment,
          workspace_id: T.any(String, UUID),
          note: T.nilable(String),
          user_id: T.nilable(String),
          pinned: T.nilable(T::Boolean)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update(assignment, workspace_id, note, user_id, pinned)
        updates = {}
        updates[:note] = note if note
        updates[:user_id] = user_id if user_id
        updates[:pinned] = pinned unless pinned.nil?

        if updates.empty?
          return T.cast(
            Failure(ServiceError.validation("No changes provided")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        DB.transaction do
          DB[:chore_assignments].where(id: assignment.id).update(updates)
          Broadcaster.object_changed("chore_assignment", assignment.id, workspace_id: workspace_id)
          # If user changed, update parent chore too
          Broadcaster.object_changed("chore", assignment.chore_id, workspace_id: workspace_id) if user_id
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)
        updated = T.must(ChoreAssignment.find(assignment.id))
        pool.add_chore_assignment(updated)
        chore = T.must(Chore.find(assignment.chore_id))
        pool.add_chore(chore)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
