# typed: true
# frozen_string_literal: true

module Votes
  # Service to delete a vote.
  #
  # @example
  #   result = Votes::Delete.call(event_id: "event-uuid", vote_id: "uuid", user_id: "uuid")
  #   result.success?  # => true
  #   result.value!    # => { message: "Vote deleted successfully" }
  module Delete
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(event_id: String, vote_id: String, user_id: String)
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, vote_id:, user_id:)
        find_vote(vote_id)
          .bind { |vote| authorize_owner(vote, user_id) }
          .bind { |vote| validate_vote_belongs_to_event(vote, event_id) }
          .bind { |vote| delete_vote(vote) }
      end

      private

      sig { params(vote_id: String).returns(Result[Vote, ServiceError]) }
      def find_vote(vote_id)
        vote = Vote.find(vote_id)
        if vote
          T.cast(Success(vote), Result[Vote, ServiceError])
        else
          T.cast(Failure(ServiceError.not_found("Vote not found")), Result[Vote, ServiceError])
        end
      end

      sig { params(vote: Vote, user_id: String).returns(Result[Vote, ServiceError]) }
      def authorize_owner(vote, user_id)
        if vote.user_id == user_id
          T.cast(Success(vote), Result[Vote, ServiceError])
        else
          T.cast(Failure(ServiceError.forbidden("Access denied")), Result[Vote, ServiceError])
        end
      end

      sig { params(vote: Vote, event_id: String).returns(Result[Vote, ServiceError]) }
      def validate_vote_belongs_to_event(vote, event_id)
        date_range = DateRange.find(vote.date_range_id)
        if date_range && date_range.event_id == event_id
          T.cast(Success(vote), Result[Vote, ServiceError])
        else
          T.cast(Failure(ServiceError.validation("Vote does not belong to this event")), Result[Vote, ServiceError])
        end
      end

      sig { params(vote: Vote).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def delete_vote(vote)
        vote_id = vote.id
        DB[:votes].where(id: vote_id).delete
        T.cast(Success({ deleted: [{ objectType: "vote", id: vote_id }] }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
