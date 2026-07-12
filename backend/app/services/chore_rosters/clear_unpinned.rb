# frozen_string_literal: true

module ChoreRosters
  # Deletes a roster's non-pinned assignments from today onward. Days already
  # past (in the event's zone) are the record of who did what and stay put.
  module ClearUnpinned
    class << self
      def call(roster_id:, workspace_id:, membership:)
        Auditable.around(
          service: "ChoreRosters::ClearUnpinned",
          actor: membership,
          subject_type: "chore_roster",
          subject_id: roster_id
        ) do
          Success()
            .bind { ChoreRoster.find_result(roster_id) }
            .bind { |roster| ChoreRosterPolicy.enforce(:edit, roster, membership: membership) }
            .bind { |roster| clear_unpinned(roster, workspace_id) }
        end
      end

      private

      def clear_unpinned(roster, workspace_id)
        deleted = []
        today = Timezones.today(Event.find(roster.event_id).timezone)

        DB.transaction do
          non_pinned_ids = DB[:chore_assignments]
                           .join(:chores, id: :chore_id)
                           .where(Sequel[:chores][:chore_roster_id] => roster.id)
                           .where(Sequel[:chore_assignments][:pinned] => false)
                           .where { Sequel[:chore_assignments][:date] >= today }
                           .select_map(Sequel[:chore_assignments][:id])

          if non_pinned_ids.any?
            DeletedItems.bulk_insert(workspace_id, "chore_assignment", non_pinned_ids)
            deleted = non_pinned_ids.map { |aid| { objectType: "choreAssignment", id: aid.to_s } }
            DB[:chore_assignments].where(id: non_pinned_ids).delete

            # Broadcast one deletion signal per assignment so clients remove them from the pool.
            # This is N pg_notify calls after a single bulk DB delete — not N individual deletes.
            non_pinned_ids.each do |aid|
              Broadcaster.object_deleted("chore_assignment", aid, topics: [Topic.workspace(workspace_id)])
            end
            Broadcaster.object_changed("chore_roster", roster.id)
          end
        end

        Success({ deleted: deleted })
      end
    end
  end
end
