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
            deleted_rows = non_pinned_ids.map do |aid|
              { workspace_id: workspace_id, object_type: "chore_assignment", object_id: aid }
            end
            DB[:deleted_items].multi_insert(deleted_rows)
            deleted = non_pinned_ids.map { |aid| { objectType: "choreAssignment", id: aid.to_s } }
            DB[:chore_assignments].where(id: non_pinned_ids).delete
          end

          # Single broadcast for the entire roster change instead of one per deleted assignment
          Broadcaster.object_changed("chore_roster", roster.id, workspace_id: workspace_id)
        end

        T.cast(Success({ deleted: deleted }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
