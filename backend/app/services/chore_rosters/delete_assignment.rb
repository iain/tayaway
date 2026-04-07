# frozen_string_literal: true

module ChoreRosters
  # Service to delete a chore assignment.
  module DeleteAssignment
    class << self
      include Dry::Monads[:result]

      def call(assignment_id:, roster_id:, workspace_id:)
        ChoreAssignment.find_result(assignment_id)
                       .bind { |assignment| validate_belongs_to_roster(assignment, roster_id) }
                       .bind { |assignment| delete(assignment, workspace_id) }
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

      def delete(assignment, workspace_id)
        chore_id = assignment.chore_id

        DB.transaction do
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "chore_assignment", object_id: assignment.id)
          DB[:chore_assignments].where(id: assignment.id).delete
          Broadcaster.object_deleted("chore_assignment", assignment.id, workspace_id: workspace_id)
          Broadcaster.object_changed("chore", chore_id, workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)
        chore = Chore.find(chore_id)
        pool.add_chore(chore)

        Success({ objects: pool.to_a, deleted: [{ objectType: "choreAssignment", id: assignment.id.to_s }] })
      end
    end
  end
end
