# frozen_string_literal: true

module ChoreRosters
  # Service to delete a chore roster. Cascades chores and assignments.
  module DeleteRoster
    class << self
      include Result::Methods

      def call(roster_id:, current_user_id:, workspace_id:)
        ChoreRoster.find_result(roster_id)
                   .bind { |roster| check_creator(roster, current_user_id) }
                   .bind { |roster| delete(roster, workspace_id) }
      end

      private

      def check_creator(roster, current_user_id)
        if roster.user_id && roster.user_id.to_s == current_user_id.to_s
          Success(roster)
        else
          Failure(ServiceError.forbidden("Only the roster creator can delete it"))
        end
      end

      def delete(roster, workspace_id)
        deleted = []

        DB.transaction do
          # Track assignment deletions for each chore
          chore_ids = DB[:chores].where(chore_roster_id: roster.id).select_map(:id)
          chore_ids.each do |cid|
            assignment_ids = DB[:chore_assignments].where(chore_id: cid).select_map(:id)
            assignment_ids.each do |aid|
              DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "chore_assignment", object_id: aid)
              Broadcaster.object_deleted("chore_assignment", aid, workspace_id: workspace_id)
              deleted << { objectType: "choreAssignment", id: aid.to_s }
            end

            # Track chore deletion
            DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "chore", object_id: cid)
            Broadcaster.object_deleted("chore", cid, workspace_id: workspace_id)
            deleted << { objectType: "chore", id: cid.to_s }
          end

          # Track roster deletion
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "chore_roster", object_id: roster.id)
          Broadcaster.object_deleted("chore_roster", roster.id, workspace_id: workspace_id)
          deleted << { objectType: "choreRoster", id: roster.id.to_s }

          # Delete roster (FK cascade handles chores and assignments)
          DB[:chore_rosters].where(id: roster.id).delete
        end

        Success({ deleted: deleted })
      end
    end
  end
end
