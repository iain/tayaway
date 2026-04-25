# frozen_string_literal: true

module Events
  # Service to delete an event.
  #
  # @example
  #   result = Events::Delete.call(event_id: "uuid", membership: membership)
  #   result.success?  # => true
  #   result.value!    # => { message: "Event deleted successfully" }
  module Delete
    extend Auditable

    audit subject_type: "event"

    class << self
      include Dry::Monads[:result]

      def call(event_id:, membership:)
        Event.find_result(event_id)
             .bind { |event| EventPolicy.enforce(:delete, event, membership: membership, has_expenses: event_has_expenses?(event)) }
             .bind { |event| delete_event(event) }
      end

      private

      def event_has_expenses?(event)
        DB[:expenses].where(event_id: event.id).any? || DB[:settlements].where(event_id: event.id).any?
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
