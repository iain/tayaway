# frozen_string_literal: true

module ChoreRosters
  # Service to delete a chore. Cascades assignments.
  module DeleteChore
    class << self
      include Dry::Monads[:result]

      def call(chore_id:, roster_id:, workspace_id:, membership:)
        Chore.find_result(chore_id)
             .bind { |chore| validate_belongs_to_roster(chore, roster_id) }
             .bind { |chore| ChorePolicy.enforce(:delete, chore, membership: membership) }
             .bind { |chore| delete(chore, roster_id, workspace_id, membership) }
      end

      def validate_belongs_to_roster(chore, roster_id)
        if chore.chore_roster_id.to_s == roster_id.to_s
          Success(chore)
        else
          Failure(ServiceError.not_found("Chore not found"))
        end
      end

      private

      def delete(chore, roster_id, workspace_id, membership)
        deleted = []

        DB.transaction do
          # Track assignment deletions
          assignment_ids = DB[:chore_assignments].where(chore_id: chore.id).select_map(:id)
          assignment_ids.each do |aid|
            DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "chore_assignment", object_id: aid)
            Broadcaster.object_deleted("chore_assignment", aid, workspace_id: workspace_id)
            deleted << { objectType: "choreAssignment", id: aid.to_s }
          end

          # Track chore deletion
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "chore", object_id: chore.id)
          Broadcaster.object_deleted("chore", chore.id, workspace_id: workspace_id)
          deleted << { objectType: "chore", id: chore.id.to_s }

          # Delete chore (cascades to assignments)
          DB[:chores].where(id: chore.id).delete

          Broadcaster.object_changed("chore_roster", roster_id, workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(membership: membership)
        roster = ChoreRoster.find(roster_id)
        pool.add_chore_roster(roster)

        Success({ objects: pool.to_a, deleted: deleted })
      end
    end
  end
end
