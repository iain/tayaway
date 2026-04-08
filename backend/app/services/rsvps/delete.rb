# frozen_string_literal: true

module Rsvps
  # Service to delete an RSVP.
  #
  # @example
  #   result = Rsvps::Delete.call(event_id: "event-uuid", rsvp_id: "uuid", membership: membership)
  module Delete
    class << self
      include Dry::Monads[:result]

      def call(event_id:, rsvp_id:, membership:)
        find_rsvp(rsvp_id)
          .bind { |rsvp| authorize(rsvp, membership) }
          .bind { |rsvp| validate_rsvp_belongs_to_event(rsvp, event_id) }
          .bind { |rsvp| delete_rsvp(rsvp, event_id) }
      end

      private

      def find_rsvp(rsvp_id)
        rsvp = Rsvp.find(rsvp_id)
        if rsvp
          Success(rsvp)
        elsif DB[:deleted_items].where(object_type: "rsvp", object_id: rsvp_id).first
          Failure(ServiceError.gone("RSVP not found"))
        else
          Failure(ServiceError.not_found("RSVP not found"))
        end
      end

      def authorize(rsvp, membership)
        RsvpPolicy.new(rsvp, membership: membership)
                  .delete
                  .bind { Success(rsvp) }
                  .or { |reason| Failure(ServiceError.forbidden(reason.to_s)) }
      end

      def validate_rsvp_belongs_to_event(rsvp, event_id)
        if rsvp.event_id == event_id
          Success(rsvp)
        else
          Failure(ServiceError.validation("RSVP does not belong to this event"))
        end
      end

      def delete_rsvp(rsvp, event_id)
        rsvp_id = rsvp.id

        event = Event.find(event_id)
        workspace_id = event.workspace_id

        DB.transaction do
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "rsvp", object_id: rsvp_id)
          DB[:rsvps].where(id: rsvp_id).delete
          Broadcaster.object_deleted("rsvp", rsvp_id, workspace_id: workspace_id)
        end

        Success({ deleted: [{ objectType: "rsvp", id: rsvp_id.to_s }] })
      end
    end
  end
end
