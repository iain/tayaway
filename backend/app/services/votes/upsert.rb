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
          .bind { |params| find_date_range(T.must(params[:date_range_id])) }
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
          T.cast(Failure(ServiceError.validation("date_range_id is required")), Result[T::Hash[Symbol, String], ServiceError])
        elsif vote_response.nil? || vote_response.empty?
          T.cast(Failure(ServiceError.validation("response is required")), Result[T::Hash[Symbol, String], ServiceError])
        elsif !VoteResponse.valid?(vote_response)
          T.cast(Failure(ServiceError.validation("Invalid response value")), Result[T::Hash[Symbol, String], ServiceError])
        elsif vote_id && !UUID_REGEX.match?(vote_id)
          T.cast(Failure(ServiceError.validation("Invalid vote ID format")), Result[T::Hash[Symbol, String], ServiceError])
        elsif vote_id && Vote.find(vote_id)
          T.cast(Failure(ServiceError.conflict("Vote ID already exists")), Result[T::Hash[Symbol, String], ServiceError])
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

      sig { params(date_range: DateRange, event_id: String).returns(Result[DateRange, ServiceError]) }
      def validate_date_range_belongs_to_event(date_range, event_id)
        if date_range.event_id == event_id
          T.cast(Success(date_range), Result[DateRange, ServiceError])
        else
          T.cast(Failure(ServiceError.validation("Date range does not belong to this event")), Result[DateRange, ServiceError])
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
          T.cast(Success({ vote_id: existing_vote.id, created: false }), Result[T::Hash[Symbol, T.untyped], ServiceError])
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
          T.cast(Success({ vote_id: new_vote_id, created: true }), Result[T::Hash[Symbol, T.untyped], ServiceError])
        end
      end
    end
  end
end
