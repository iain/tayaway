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
  #     comment: "Looks good!"
  #   )
  #   result.success?  # => true
  #   result.value!    # => { vote_id: "uuid", created: true }
  module Upsert
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event_id: String,
          user_id: String,
          date_range_id: T.nilable(String),
          vote_response: T.nilable(String),
          comment: T.nilable(String),
          vote_id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, user_id:, date_range_id:, vote_response:, comment:, vote_id: nil)
        validate_params(date_range_id, vote_response, vote_id)
          .bind { |params| find_date_range(params[:date_range_id]) }
          .bind { |date_range| validate_date_range_belongs_to_event(date_range, event_id) }
          .bind { |date_range| upsert_vote(date_range, user_id, T.must(vote_response), comment, vote_id) }
      end

      private

      UUID_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      sig do
        params(
          date_range_id: T.nilable(String),
          vote_response: T.nilable(String),
          vote_id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, String], ServiceError])
      end
      def validate_params(date_range_id, vote_response, vote_id)
        if date_range_id.nil? || date_range_id.empty?
          Failure(ServiceError.validation("date_range_id is required"))
        elsif vote_response.nil? || vote_response.empty?
          Failure(ServiceError.validation("response is required"))
        elsif !VoteResponse.valid?(vote_response)
          Failure(ServiceError.validation("Invalid response value"))
        elsif vote_id && !UUID_REGEX.match?(vote_id)
          Failure(ServiceError.validation("Invalid vote ID format"))
        elsif vote_id && Vote.find(vote_id)
          Failure(ServiceError.conflict("Vote ID already exists"))
        else
          Success({ date_range_id: date_range_id, vote_response: vote_response })
        end
      end

      sig { params(date_range_id: String).returns(Result[DateRange, ServiceError]) }
      def find_date_range(date_range_id)
        date_range = DateRange.find(date_range_id)
        if date_range
          Success(date_range)
        else
          Failure(ServiceError.validation("Date range not found"))
        end
      end

      sig { params(date_range: DateRange, event_id: String).returns(Result[DateRange, ServiceError]) }
      def validate_date_range_belongs_to_event(date_range, event_id)
        if date_range.event_id == event_id
          Success(date_range)
        else
          Failure(ServiceError.validation("Date range does not belong to this event"))
        end
      end

      sig do
        params(
          date_range: DateRange,
          user_id: String,
          vote_response: String,
          comment: T.nilable(String),
          vote_id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def upsert_vote(date_range, user_id, vote_response, comment, vote_id)
        existing_vote = Vote.find_by_date_range_and_user(date_range.id, user_id)
        clean_comment = comment&.empty? ? nil : comment

        if existing_vote
          DB[:votes].where(id: existing_vote.id).update(
            response: vote_response,
            comment: clean_comment,
            updated_at: Time.now
          )
          Success({ vote_id: existing_vote.id, created: false })
        else
          now = Time.now
          new_vote_id = vote_id || SecureRandom.uuid

          DB[:votes].insert(
            id: new_vote_id,
            date_range_id: date_range.id,
            user_id: user_id,
            response: vote_response,
            comment: clean_comment,
            created_at: now,
            updated_at: now
          )
          Success({ vote_id: new_vote_id, created: true })
        end
      end
    end
  end
end
