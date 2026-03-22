# typed: true
# frozen_string_literal: true

module Votes
  # Service to create or update a vote for an event date range.
  #
  # @example
  #   result = Votes::Upsert.call(
  #     event_id: "event-uuid",
  #     user_id: "uuid",
  #     date_range_id: "dr-uuid",
  #     vote_response: "yes",
  #     comment: "Looks good!",
  #     vote_id: "client-generated-uuid"
  #   )
  #   result.success?  # => true
  #   result.value!    # => { vote_id: "uuid", created: true }
  module Upsert
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          date_range_id: T.nilable(String),
          vote_response: T.nilable(String),
          comment: T.nilable(String),
          vote_id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, user_id:, date_range_id:, vote_response:, comment:, vote_id:)
        # Idempotent replay: if client provided an ID that already exists, return it
        if vote_id
          existing = Vote.find(vote_id)
          if existing
            return T.cast(Success({ vote_id: existing.id, created: false }), Result[T::Hash[Symbol, T.untyped], ServiceError])
          end
        end

        validate_params(date_range_id, vote_response, vote_id)
          .bind { |params| find_date_range(T.must(params[:date_range_id])) }
          .bind { |date_range| validate_date_range_belongs_to_event(date_range, event_id) }
          .bind { |date_range| validate_poll_open(date_range) }
          .bind { |date_range| upsert_vote(date_range, user_id, T.must(vote_response), comment, T.must(vote_id)) }
      end

      private

      sig do
        params(
          date_range_id: T.nilable(String),
          vote_response: T.nilable(String),
          vote_id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, String], ServiceError])
      end
      def validate_params(date_range_id, vote_response, vote_id)
        if date_range_id.nil? || date_range_id.empty?
          T.cast(Failure(ServiceError.validation("date_range_id is required")), Result[T::Hash[Symbol, String], ServiceError])
        elsif vote_response.nil? || vote_response.empty?
          T.cast(Failure(ServiceError.validation("response is required")), Result[T::Hash[Symbol, String], ServiceError])
        elsif !VoteResponse.valid?(vote_response)
          T.cast(Failure(ServiceError.validation("Invalid response value")), Result[T::Hash[Symbol, String], ServiceError])
        elsif vote_id.nil? || vote_id.empty?
          T.cast(Failure(ServiceError.validation("id is required")), Result[T::Hash[Symbol, String], ServiceError])
        elsif !UUID::REGEX.match?(vote_id)
          T.cast(Failure(ServiceError.validation("Invalid vote ID format")), Result[T::Hash[Symbol, String], ServiceError])
        else
          T.cast(Success({ date_range_id: date_range_id, vote_response: vote_response }), Result[T::Hash[Symbol, String], ServiceError])
        end
      end

      sig { params(date_range_id: String).returns(Result[DateRange, ServiceError]) }
      def find_date_range(date_range_id)
        date_range = DateRange.find(date_range_id)
        if date_range
          T.cast(Success(date_range), Result[DateRange, ServiceError])
        else
          T.cast(Failure(ServiceError.validation("Date range not found")), Result[DateRange, ServiceError])
        end
      end

      sig { params(date_range: DateRange, event_id: T.any(String, UUID)).returns(Result[DateRange, ServiceError]) }
      def validate_date_range_belongs_to_event(date_range, event_id)
        poll = DatePoll.find(date_range.date_poll_id)
        if poll && poll.event_id == event_id
          T.cast(Success(date_range), Result[DateRange, ServiceError])
        else
          T.cast(Failure(ServiceError.validation("Date range does not belong to this event")), Result[DateRange, ServiceError])
        end
      end

      sig { params(date_range: DateRange).returns(Result[DateRange, ServiceError]) }
      def validate_poll_open(date_range)
        poll = DatePoll.find(date_range.date_poll_id)
        if poll && poll.open?
          T.cast(Success(date_range), Result[DateRange, ServiceError])
        else
          T.cast(Failure(ServiceError.validation("Poll is not open for voting")), Result[DateRange, ServiceError])
        end
      end

      sig do
        params(
          date_range: DateRange,
          user_id: T.any(String, UUID),
          vote_response: String,
          comment: T.nilable(String),
          vote_id: String
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def upsert_vote(date_range, user_id, vote_response, comment, vote_id)
        if comment && comment.length > ValidationLimits::VOTE_COMMENT
          return T.cast(
            Failure(ServiceError.validation("Comment is too long (maximum 1000 characters)")),
            Result[T::Hash[Symbol, T.untyped], ServiceError]
          )
        end

        existing_vote = Vote.find_by_date_range_and_user(date_range.id, user_id)
        clean_comment = comment&.empty? ? nil : comment
        result_vote_id = T.let(nil, T.nilable(T.any(String, UUID)))
        created = T.let(false, T::Boolean)

        # Get workspace_id by traversing: date_range -> date_poll -> event -> workspace_id
        poll = T.must(DatePoll.find(date_range.date_poll_id))
        event = T.must(Event.find(poll.event_id))
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

            Broadcaster.object_changed("vote", T.must(result_vote_id), workspace_id: workspace_id)
          end
        rescue Sequel::UniqueConstraintViolation
          existing = Vote.find_by_date_range_and_user(date_range.id, user_id)
          result_vote_id = T.must(existing).id
          created = false
        end

        T.cast(Success({ vote_id: result_vote_id, created: created }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
