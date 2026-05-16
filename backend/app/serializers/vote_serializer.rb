# frozen_string_literal: true

class VoteSerializer
  extend PoolObjectSerializer

  class << self
    def broadcast_audiences_for(vote)
      ws_id = DB[:date_ranges]
              .join(:date_polls, id: :date_poll_id)
              .join(:events, id: Sequel[:date_polls][:event_id])
              .where(Sequel[:date_ranges][:id] => vote.date_range_id)
              .get(Sequel[:events][:workspace_id])
      [WS_AUD.call(ws_id)]
    end

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
