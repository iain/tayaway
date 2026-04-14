# frozen_string_literal: true

class ChoreSerializer
  class << self
    def serialize_batch(chores, pool:)
      return [] if chores.empty?

      chore_ids = chores.map { |c| c.id.to_s }
      all_assignments = ChoreAssignment.for_chores(chore_ids)
      assignments_by_chore = all_assignments.group_by { |a| a.chore_id.to_s }

      if pool
        pool.add(:chore_assignment, all_assignments) if all_assignments.any?
      end

      chores.map do |chore|
        assignments = assignments_by_chore[chore.id.to_s] || []
        {
          id: chore.id.to_s,
          objectType: "chore",
          choreRosterId: chore.chore_roster_id.to_s,
          name: chore.name,
          peoplePerDay: chore.people_per_day,
          position: chore.position,
          assignmentIds: assignments.map { |a| a.id.to_s },
          createdAt: chore.created_at.iso8601(3),
          updatedAt: chore.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_chore) = {}
    def policy_context_batch(_chores) = {}
  end
end
