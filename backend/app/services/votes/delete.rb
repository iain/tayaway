# typed: true
# frozen_string_literal: true

module Votes
  # Service to delete a vote.
  #
  # @example
  #   result = Votes::Delete.call(event: event, vote_id: "uuid", user_id: "uuid")
  #   result.success?  # => true
  #   result.value!    # => { message: "Vote deleted successfully" }
  module Delete
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(event: Event, vote_id: String, user_id: String)
          .returns(Result[T::Hash[Symbol, String], ServiceError])
      end
      def call(event:, vote_id:, user_id:)
        find_vote(vote_id)
          .bind { |vote| authorize_owner(vote, user_id) }
          .bind { |vote| validate_vote_belongs_to_event(vote, event) }
          .bind { |vote| delete_vote(vote) }
      end

      private

      sig { params(vote_id: String).returns(Result[Vote, ServiceError]) }
      def find_vote(vote_id)
        vote = Vote.first(id: vote_id)
        if vote
          Success(vote)
        else
          Failure(ServiceError.not_found("Vote not found"))
        end
      end

      sig { params(vote: Vote, user_id: String).returns(Result[Vote, ServiceError]) }
      def authorize_owner(vote, user_id)
        if vote.user_id == user_id
          Success(vote)
        else
          Failure(ServiceError.forbidden("Access denied"))
        end
      end

      sig { params(vote: Vote, event: Event).returns(Result[Vote, ServiceError]) }
      def validate_vote_belongs_to_event(vote, event)
        date_range = vote.date_range
        if date_range&.event_id == event.id
          Success(vote)
        else
          Failure(ServiceError.validation("Vote does not belong to this event"))
        end
      end

      sig { params(vote: Vote).returns(Result[T::Hash[Symbol, String], ServiceError]) }
      def delete_vote(vote)
        vote.destroy
        Success({ message: "Vote deleted successfully" })
      end
    end
  end
end
