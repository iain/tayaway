# frozen_string_literal: true

class VoteSerializer
  class << self
    def serialize_batch(votes, pool:)
      votes.map do |vote|
        {
          id: vote.id.to_s,
          objectType: "vote",
          dateRangeId: vote.date_range_id.to_s,
          userId: vote.user_id.to_s,
          response: vote.response,
          comment: vote.comment,
          createdAt: vote.created_at.iso8601(3),
          updatedAt: vote.updated_at.iso8601(3)
        }
      end
    end
  end
end
