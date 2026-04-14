# frozen_string_literal: true

class ChoreAssignmentSerializer
  class << self
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

    def policy_context(_assignment) = {}
    def policy_context_batch(_assignments) = {}
  end
end
