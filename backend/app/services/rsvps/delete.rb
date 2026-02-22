# typed: true
# frozen_string_literal: true

module Rsvps
  # Service to delete an RSVP.
  #
  # @example
  #   result = Rsvps::Delete.call(event_id: "event-uuid", rsvp_id: "uuid", user_id: "uuid")
  module Delete
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(event_id: T.any(String, UUID), rsvp_id: String, user_id: T.any(String, UUID))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, rsvp_id:, user_id:)
        find_rsvp(rsvp_id)
          .bind { |rsvp| authorize_owner(rsvp, user_id) }
          .bind { |rsvp| validate_rsvp_belongs_to_event(rsvp, event_id) }
          .bind { |rsvp| delete_rsvp(rsvp, event_id) }
      end

      private

      sig { params(rsvp_id: String).returns(Result[Rsvp, ServiceError]) }
      def find_rsvp(rsvp_id)
        rsvp = Rsvp.find(rsvp_id)
        if rsvp
          T.cast(Success(rsvp), Result[Rsvp, ServiceError])
        elsif DB[:deleted_items].where(object_type: "rsvp", object_id: rsvp_id).first
          T.cast(Failure(ServiceError.gone("RSVP not found")), Result[Rsvp, ServiceError])
        else
          T.cast(Failure(ServiceError.not_found("RSVP not found")), Result[Rsvp, ServiceError])
        end
      end

      sig { params(rsvp: Rsvp, user_id: T.any(String, UUID)).returns(Result[Rsvp, ServiceError]) }
      def authorize_owner(rsvp, user_id)
        if rsvp.user_id == user_id
          T.cast(Success(rsvp), Result[Rsvp, ServiceError])
        else
          T.cast(Failure(ServiceError.forbidden("Access denied")), Result[Rsvp, ServiceError])
        end
      end

      sig { params(rsvp: Rsvp, event_id: T.any(String, UUID)).returns(Result[Rsvp, ServiceError]) }
      def validate_rsvp_belongs_to_event(rsvp, event_id)
        if rsvp.event_id == event_id
          T.cast(Success(rsvp), Result[Rsvp, ServiceError])
        else
          T.cast(Failure(ServiceError.validation("RSVP does not belong to this event")), Result[Rsvp, ServiceError])
        end
      end

      sig { params(rsvp: Rsvp, event_id: T.any(String, UUID)).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def delete_rsvp(rsvp, event_id)
        rsvp_id = rsvp.id

        event = Event.find(event_id)
        workspace_id = T.must(event).workspace_id

        DB.transaction do
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "rsvp", object_id: rsvp_id)
          DB[:rsvps].where(id: rsvp_id).delete
          Broadcaster.object_deleted("rsvp", rsvp_id, workspace_id: workspace_id)
        end

        T.cast(Success({ deleted: [{ objectType: "rsvp", id: rsvp_id.to_s }] }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
