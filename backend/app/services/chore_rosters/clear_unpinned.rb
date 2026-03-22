# typed: true
# frozen_string_literal: true

module ChoreRosters
  # Deletes all non-pinned assignments for a roster.
  module ClearUnpinned
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          roster_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(roster_id:, workspace_id:)
        ChoreRoster.find_result(roster_id)
                   .bind { |roster| clear_unpinned(roster, workspace_id) }
      end

      private

      sig do
        params(
          roster: ChoreRoster,
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def clear_unpinned(roster, workspace_id)
        deleted = T.let([], T::Array[T::Hash[Symbol, T.untyped]])

        DB.transaction do
          non_pinned_ids = DB[:chore_assignments]
                           .join(:chores, id: :chore_id)
                           .where(Sequel[:chores][:chore_roster_id] => roster.id)
                           .where(Sequel[:chore_assignments][:pinned] => false)
                           .select_map(Sequel[:chore_assignments][:id])

          if non_pinned_ids.any?
            DeletedItems.bulk_insert(workspace_id, "chore_assignment", non_pinned_ids)
            deleted = non_pinned_ids.map { |aid| { objectType: "choreAssignment", id: aid.to_s } }
            DB[:chore_assignments].where(id: non_pinned_ids).delete

            # Broadcast one deletion signal per assignment so clients remove them from the pool.
            # This is N pg_notify calls after a single bulk DB delete — not N individual deletes.
            non_pinned_ids.each do |aid|
              Broadcaster.object_deleted("chore_assignment", aid, workspace_id: workspace_id)
            end
            Broadcaster.object_changed("chore_roster", roster.id, workspace_id: workspace_id)
          end
        end

        T.cast(Success({ deleted: deleted }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
