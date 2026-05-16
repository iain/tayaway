# frozen_string_literal: true

class ChoreAssignmentSerializer
  extend PoolObjectSerializer

  class << self
    def broadcast_audiences_for(assignment)
      ws_id = DB[:chores]
              .join(:chore_rosters, id: :chore_roster_id)
              .join(:events, id: Sequel[:chore_rosters][:event_id])
              .where(Sequel[:chores][:id] => assignment.chore_id)
              .get(Sequel[:events][:workspace_id])
      [WS_AUD.call(ws_id)]
    end

    def serialize_batch(assignments, pool:)
      assignments.map do |assignment|
        {
          id: assignment.id.to_s,
          objectType: "choreAssignment",
          choreId: assignment.chore_id.to_s,
          userId: assignment.user_id.to_s,
          date: assignment.date.iso8601,
          pinned: assignment.pinned,
          note: assignment.note,
          createdAt: assignment.created_at.iso8601(3),
          updatedAt: assignment.updated_at.iso8601(3)
        }
      end
    end
  end
end
