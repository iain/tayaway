# typed: true
# frozen_string_literal: true

module ChoreRosters
  # Service to delete a chore assignment.
  module DeleteAssignment
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          assignment_id: T.any(String, UUID),
          roster_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(assignment_id:, roster_id:, workspace_id:)
        ChoreAssignment.find_result(assignment_id)
                       .bind { |assignment| validate_belongs_to_roster(assignment, roster_id) }
                       .bind { |assignment| delete(assignment, workspace_id) }
      end

      sig do
        params(
          assignment: ChoreAssignment,
          roster_id: T.any(String, UUID)
        ).returns(Result[ChoreAssignment, ServiceError])
      end
      def validate_belongs_to_roster(assignment, roster_id)
        chore = Chore.find(assignment.chore_id)
        if chore && chore.chore_roster_id.to_s == roster_id.to_s
          T.cast(Success(assignment), Result[ChoreAssignment, ServiceError])
        else
          T.cast(Failure(ServiceError.not_found("Assignment not found")), Result[ChoreAssignment, ServiceError])
        end
      end

      private

      sig do
        params(
          assignment: ChoreAssignment,
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def delete(assignment, workspace_id)
        chore_id = assignment.chore_id

        DB.transaction do
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "chore_assignment", object_id: assignment.id)
          DB[:chore_assignments].where(id: assignment.id).delete
          Broadcaster.object_deleted("chore_assignment", assignment.id, workspace_id: workspace_id)
          Broadcaster.object_changed("chore", chore_id, workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)
        chore = T.must(Chore.find(chore_id))
        pool.add_chore(chore)

        T.cast(
          Success({ objects: pool.to_a, deleted: [{ objectType: "choreAssignment", id: assignment.id.to_s }] }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end
    end
  end
end
