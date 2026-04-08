# frozen_string_literal: true

module Events
  # Service to delete an event.
  #
  # @example
  #   result = Events::Delete.call(event_id: "uuid", membership: membership)
  #   result.success?  # => true
  #   result.value!    # => { message: "Event deleted successfully" }
  module Delete
    class << self
      include Dry::Monads[:result]

      def call(event_id:, membership:)
        Event.find_result(event_id)
             .bind { |event| authorize(event, membership) }
             .bind { |event| delete_event(event) }
      end

      private

      def authorize(event, membership)
        EventPolicy.new(event, membership: membership)
                   .delete
                   .bind { Success(event) }
                   .or { |reason| Failure(ServiceError.forbidden(reason.to_s)) }
      end

      def delete_event(event)
        event_id = event.id
        workspace_id = event.workspace_id

        DB.transaction do
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "event", object_id: event_id)
          DB[:events].where(id: event_id).delete
          Broadcaster.object_deleted("event", event_id, workspace_id: workspace_id)
        end

        APP_LOGGER.info { "[Events::Delete] Event #{event_id} deleted from workspace #{workspace_id}" }
        Success({ deleted: [{ objectType: "event", id: event_id.to_s }] })
      end
    end
  end
end
