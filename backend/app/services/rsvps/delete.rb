# frozen_string_literal: true

module Rsvps
  # Service to delete an RSVP.
  #
  # @example
  #   result = Rsvps::Delete.call(event_id: "event-uuid", rsvp_id: "uuid", membership: membership)
  module Delete
    class << self
      def call(event_id:, rsvp_id:, membership:)
        Auditable.around(
          service: "Rsvps::Delete",
          actor: membership,
          subject_type: "rsvp",
          subject_id: rsvp_id
        ) do
          Success()
            .bind { find_rsvp(rsvp_id) }
            .bind { |rsvp| validate_rsvp_belongs_to_event(rsvp, event_id) }
            .bind { |rsvp| delete_rsvp(rsvp, event_id) }
        end
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
          Broadcaster.object_deleted("rsvp", rsvp_id, topics: [Topic.workspace(workspace_id)])
        end

        Success({ deleted: [{ objectType: "rsvp", id: rsvp_id.to_s }] })
      end
    end
  end
end
