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
      include Dry::Monads[:result]

      def call(event_id:, membership:, date_range_id:, vote_response:, comment:, vote_id:)
        user_id = membership.user_id

        # Idempotent replay: if client provided an ID that already exists, return it
        if vote_id
          existing = Vote.find(vote_id)
          if existing
            return Success({ vote_id: existing.id, created: false })
          end
        end

        # Generate a server-side ID if the client did not provide one (backwards
        # compatibility with commands queued before client-ID enforcement).
        resolved_vote_id = vote_id.nil? || vote_id.empty? ? SecureRandom.uuid : vote_id

        validate_params(date_range_id, vote_response)
          .bind { |params| find_date_range(params[:date_range_id]) }
          .bind { |date_range| validate_date_range_belongs_to_event(date_range, event_id) }
          .bind { |date_range| DateRangePolicy.enforce(:create_vote, date_range, membership: membership) }
          .bind { |date_range| validate_poll_open(date_range) }
          .bind { |date_range| upsert_vote(date_range, user_id, vote_response, comment, resolved_vote_id) }
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

        existing_vote = Vote.find_by_date_range_and_user(date_range.id, user_id)
        clean_comment = comment&.empty? ? nil : comment
        result_vote_id = nil
        created = false

        # Get workspace_id by traversing: date_range -> date_poll -> event -> workspace_id
        poll = DatePoll.find(date_range.date_poll_id)
        event = Event.find(poll.event_id)
        workspace_id = event.workspace_id

        begin
          DB.transaction do
            now = Time.now

            if existing_vote
              DB[:votes].where(id: existing_vote.id).update(
                response: vote_response,
                comment: clean_comment,
                updated_at: now
              )
              result_vote_id = existing_vote.id
              created = false
            else
              result_vote_id = vote_id

              DB[:votes].insert(
                id: result_vote_id,
                date_range_id: date_range.id,
                user_id: user_id,
                response: vote_response,
                comment: clean_comment,
                created_at: now,
                updated_at: now
              )
              created = true
            end

            Broadcaster.object_changed("vote", result_vote_id, workspace_id: workspace_id)
          end
        rescue Sequel::UniqueConstraintViolation
          existing = Vote.find_by_date_range_and_user(date_range.id, user_id)
          result_vote_id = existing.id
          created = false
          Broadcaster.object_changed("vote", result_vote_id, workspace_id: workspace_id)
        end

        Success({ vote_id: result_vote_id, created: created })
      end
    end
  end
end
