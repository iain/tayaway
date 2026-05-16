# frozen_string_literal: true

module ChoreRosters
  # Service to delete a chore assignment.
  module DeleteAssignment
    class << self
      def call(assignment_id:, roster_id:, workspace_id:, membership:)
        Auditable.around(
          service: "ChoreRosters::DeleteAssignment",
          actor: membership,
          subject_type: "chore_assignment",
          subject_id: assignment_id
        ) do
          Success()
            .bind { ChoreAssignment.find_result(assignment_id) }
            .bind { |assignment| validate_belongs_to_roster(assignment, roster_id) }
            .bind { |assignment| ChoreAssignmentPolicy.enforce(:delete, assignment, membership: membership) }
            .bind { |assignment| delete(assignment, workspace_id, membership) }
        end
      end

      def validate_belongs_to_roster(assignment, roster_id)
        chore = Chore.find(assignment.chore_id)
        if chore && chore.chore_roster_id.to_s == roster_id.to_s
          Success(assignment)
        else
          Failure(ServiceError.not_found("Assignment not found"))
        end
      end

      private

      def delete(assignment, workspace_id, membership)
        chore_id = assignment.chore_id

        DB.transaction do
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "chore_assignment", object_id: assignment.id)
          DB[:chore_assignments].where(id: assignment.id).delete
          Broadcaster.object_deleted("chore_assignment", assignment.id, workspace_id: workspace_id)
          Broadcaster.object_changed("chore", chore_id)
        end

        pool = PoolSerializer.new(membership: membership)
        chore = Chore.find(chore_id)
        pool.add(:chore, [chore])

        Success({ objects: pool.to_a, deleted: [{ objectType: "choreAssignment", id: assignment.id.to_s }] })
      end
    end
  end
end
