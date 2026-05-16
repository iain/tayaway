# frozen_string_literal: true

module Votes
  # Service to delete a vote.
  #
  # @example
  #   result = Votes::Delete.call(event_id: "event-uuid", vote_id: "uuid", membership: membership)
  #   result.success?  # => true
  #   result.value!    # => { message: "Vote deleted successfully" }
  module Delete
    class << self
      def call(event_id:, vote_id:, membership:)
        Auditable.around(
          service: "Votes::Delete",
          actor: membership,
          subject_type: "vote",
          subject_id: vote_id
        ) do
          Success()
            .bind { find_vote(vote_id) }
            .bind { |vote| VotePolicy.enforce(:delete, vote, membership: membership) }
            .bind { |vote| validate_vote_belongs_to_event(vote, event_id) }
            .bind { |vote| validate_poll_open(vote) }
            .bind { |vote| delete_vote(vote, event_id) }
        end
      end

      private

      def find_vote(vote_id)
        vote = Vote.find(vote_id)
        if vote
          Success(vote)
        elsif DB[:deleted_items].where(object_type: "vote", object_id: vote_id).first
          Failure(ServiceError.gone("Vote not found"))
        else
          Failure(ServiceError.not_found("Vote not found"))
        end
      end

      def validate_vote_belongs_to_event(vote, event_id)
        date_range = DateRange.find(vote.date_range_id)
        if date_range
          poll = DatePoll.find(date_range.date_poll_id)
          if poll && poll.event_id == event_id
            return Success(vote)
          end
        end
        Failure(ServiceError.validation("Vote does not belong to this event"))
      end

      def validate_poll_open(vote)
        date_range = DateRange.find(vote.date_range_id)
        if date_range
          poll = DatePoll.find(date_range.date_poll_id)
          if poll && poll.open?
            return Success(vote)
          end
        end
        Failure(ServiceError.validation("Poll is not open for voting"))
      end

      def delete_vote(vote, event_id)
        vote_id = vote.id

        # Get workspace_id from the event
        event = Event.find(event_id)
        workspace_id = event.workspace_id

        DB.transaction do
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "vote", object_id: vote_id)
          DB[:votes].where(id: vote_id).delete
          Broadcaster.object_deleted("vote", vote_id, topics: [Topic.workspace(workspace_id)])
        end

        Success({ deleted: [{ objectType: "vote", id: vote_id.to_s }] })
      end
    end
  end
end
