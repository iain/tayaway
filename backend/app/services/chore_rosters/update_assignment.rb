# frozen_string_literal: true

module ChoreRosters
  # Service to update a chore assignment (note, user_id).
  module UpdateAssignment
    class << self
      include Dry::Monads[:result]

      def call(assignment_id:, roster_id:, workspace_id:, membership:, note: nil, user_id: nil, pinned: nil)
        ChoreAssignment.find_result(assignment_id)
                       .bind { |assignment| validate_belongs_to_roster(assignment, roster_id) }
                       .bind { |assignment| ChoreAssignmentPolicy.enforce(:edit, assignment, membership: membership) }
                       .bind { |assignment| update(assignment, workspace_id, note, user_id, pinned, membership) }
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

      def update(assignment, workspace_id, note, user_id, pinned, membership)
        updates = {}
        updates[:note] = note unless note.nil?
        updates[:user_id] = user_id if user_id
        updates[:pinned] = pinned unless pinned.nil?

        if updates.empty?
          return Failure(ServiceError.validation("No changes provided"))
        end

        DB.transaction do
          DB[:chore_assignments].where(id: assignment.id).update(updates)
          Broadcaster.object_changed("chore_assignment", assignment.id, workspace_id: workspace_id)
          # If user changed, update parent chore too
          Broadcaster.object_changed("chore", assignment.chore_id, workspace_id: workspace_id) if user_id
        end

        pool = PoolSerializer.new(membership: membership)
        updated = ChoreAssignment.find(assignment.id)
        pool.add_chore_assignment(updated)
        chore = Chore.find(assignment.chore_id)
        pool.add_chore(chore)

        Success({ objects: pool.to_a })
      end
    end
  end
end
