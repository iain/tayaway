# frozen_string_literal: true

module Votes
  # Service to create or update a vote for an event date range.
  #
  # @example
  #   result = Votes::Upsert.call(
  #     event_id: "event-uuid",
  #     membership: membership,
  #     date_range_id: "dr-uuid",
  #     vote_response: "yes",
  #     comment: "Looks good!",
  #     vote_id: "client-generated-uuid"
  #   )
  #   result.success?  # => true
  #   result.value!    # => { vote_id: "uuid", created: true }
  module Upsert
    class << self
      def call(event_id:, membership:, date_range_id:, vote_response:, comment:, vote_id:)
        user_id = membership.user_id

        # Generate a server-side ID if the client did not provide one (backwards
        # compatibility with commands queued before client-ID enforcement).
        resolved_vote_id = vote_id.nil? || vote_id.empty? ? SecureRandom.uuid : vote_id

        Auditable.around(
          service: "Votes::Upsert",
          actor: membership,
          subject_type: "vote",
          subject_id: resolved_vote_id,
          context: { response: vote_response }
        ) do
          Success()
            .bind { validate_params(date_range_id, vote_response) }
            .bind { |params| find_date_range(params[:date_range_id]) }
            .bind { |date_range| validate_date_range_belongs_to_event(date_range, event_id) }
            .bind { |date_range| DateRangePolicy.enforce(:create_vote, date_range, membership: membership) }
            .bind { |date_range| validate_poll_open(date_range) }
            .bind { |date_range| upsert_vote(date_range, user_id, vote_response, comment, resolved_vote_id) }
        end
      end

      private

      def validate_params(date_range_id, vote_response)
        if date_range_id.nil? || date_range_id.empty?
          Failure(ServiceError.validation("date_range_id is required"))
        elsif vote_response.nil? || vote_response.empty?
          Failure(ServiceError.validation("response is required"))
        elsif !VoteResponse.valid?(vote_response)
          Failure(ServiceError.validation("Invalid response value"))
        else
          Success({ date_range_id: date_range_id, vote_response: vote_response })
        end
      end

      def find_date_range(date_range_id)
        date_range = DateRange.find(date_range_id)
        if date_range
          Success(date_range)
        else
          Failure(ServiceError.validation("Date range not found"))
        end
      end

      def validate_date_range_belongs_to_event(date_range, event_id)
        poll = DatePoll.find(date_range.date_poll_id)
        if poll && poll.event_id == event_id
          Success(date_range)
        else
          Failure(ServiceError.validation("Date range does not belong to this event"))
        end
      end

      def validate_poll_open(date_range)
        poll = DatePoll.find(date_range.date_poll_id)
        if poll && poll.open?
          Success(date_range)
        else
          Failure(ServiceError.validation("Poll is not open for voting"))
        end
      end

      def upsert_vote(date_range, user_id, vote_response, comment, vote_id)
        if comment && comment.length > ValidationLimits::VOTE_COMMENT
          return Failure(ServiceError.validation("Comment is too long (maximum 1000 characters)"))
        end

        clean_comment = comment&.empty? ? nil : comment

        # Get workspace_id by traversing: date_range -> date_poll -> event -> workspace_id
        poll = DatePoll.find(date_range.date_poll_id)
        event = Event.find(poll.event_id)
        workspace_id = event.workspace_id

        row = nil
        DB.transaction do
          now = Time.now
          row = DB[:votes]
                .returning(:id, Sequel.lit("(xmax = 0) AS created"))
                .insert_conflict(
                  target: %i[date_range_id user_id],
                  update: {
                    response: Sequel[:excluded][:response],
                    comment: Sequel[:excluded][:comment],
                    updated_at: Sequel[:excluded][:updated_at]
                  }
                )
                .insert(
                  id: vote_id,
                  date_range_id: date_range.id,
                  user_id: user_id,
                  response: vote_response,
                  comment: clean_comment,
                  created_at: now,
                  updated_at: now
                )
                .first

          Broadcaster.object_changed("vote", row[:id], workspace_id: workspace_id)
        end

        Success({ vote_id: row[:id], created: row[:created] })
      end
    end
  end
end
