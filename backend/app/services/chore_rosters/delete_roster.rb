# frozen_string_literal: true

module ChoreRosters
  # Service to delete a chore roster. Cascades chores and assignments.
  module DeleteRoster
    class << self
      def call(roster_id:, membership:, workspace_id:)
        Auditable.around(
          service: "ChoreRosters::DeleteRoster",
          actor: membership,
          subject_type: "chore_roster",
          subject_id: roster_id
        ) do
          Success()
            .bind { ChoreRoster.find_result(roster_id) }
            .bind { |roster| ChoreRosterPolicy.enforce(:delete, roster, membership: membership) }
            .bind { |roster| delete(roster, workspace_id) }
        end
      end

      private

      def delete(roster, workspace_id)
        deleted = []

        DB.transaction do
          # Track assignment deletions for each chore
          chore_ids = DB[:chores].where(chore_roster_id: roster.id).select_map(:id)
          chore_ids.each do |cid|
            assignment_ids = DB[:chore_assignments].where(chore_id: cid).select_map(:id)
            assignment_ids.each do |aid|
              DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "chore_assignment", object_id: aid)
              Broadcaster.object_deleted("chore_assignment", aid, topics: [Topic.workspace(workspace_id)])
              deleted << { objectType: "choreAssignment", id: aid.to_s }
            end

            # Track chore deletion
            DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "chore", object_id: cid)
            Broadcaster.object_deleted("chore", cid, topics: [Topic.workspace(workspace_id)])
            deleted << { objectType: "chore", id: cid.to_s }
          end

          # Track roster deletion
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "chore_roster", object_id: roster.id)
          Broadcaster.object_deleted("chore_roster", roster.id, topics: [Topic.workspace(workspace_id)])
          deleted << { objectType: "choreRoster", id: roster.id.to_s }

          # Delete roster (FK cascade handles chores and assignments)
          DB[:chore_rosters].where(id: roster.id).delete
        end

        Success({ deleted: deleted })
      end
    end
  end
end
