# typed: true
# frozen_string_literal: true

module ChoreRosters
  # Service to delete a chore. Cascades assignments.
  module DeleteChore
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          chore_id: T.any(String, UUID),
          roster_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(chore_id:, roster_id:, workspace_id:)
        Chore.find_result(chore_id)
             .bind { |chore| delete(chore, roster_id, workspace_id) }
      end

      private

      sig do
        params(
          chore: Chore,
          roster_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def delete(chore, roster_id, workspace_id)
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

        pool = PoolSerializer.new(workspace_id: workspace_id)
        roster = T.must(ChoreRoster.find(roster_id))
        pool.add_chore_roster(roster)

        T.cast(
          Success({ objects: pool.to_a, deleted: deleted }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end
    end
  end
end
