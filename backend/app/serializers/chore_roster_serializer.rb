# frozen_string_literal: true

class ChoreRosterSerializer
  class << self
    def serialize_batch(rosters, pool:)
      return [] if rosters.empty?

      roster_ids = rosters.map { |r| r.id.to_s }
      chores = Chore.for_rosters(roster_ids)
      chores_by_roster = chores.group_by { |c| c.chore_roster_id.to_s }

      pool.add(:chore, chores) if pool && chores.any?

      rosters.map do |roster|
        roster_chores = chores_by_roster[roster.id.to_s] || []
        {
          id: roster.id.to_s,
          objectType: "choreRoster",
          eventId: roster.event_id.to_s,
          userId: roster.user_id&.to_s,
          choreIds: roster_chores.map { |c| c.id.to_s },
          createdAt: roster.created_at.iso8601(3),
          updatedAt: roster.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_roster) = {}
    def policy_context_batch(_rosters) = {}
  end
end
