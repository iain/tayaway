# typed: true
# frozen_string_literal: true

module Events
  # Service to delete an event.
  #
  # @example
  #   result = Events::Delete.call(event_id: "uuid", current_user_id: "uuid")
  #   result.success?  # => true
  #   result.value!    # => { message: "Event deleted successfully" }
  module Delete
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(event_id: T.any(String, UUID), current_user_id: T.any(String, UUID))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, current_user_id:)
        Event.find_result(event_id)
             .bind { |event| Event.authorize_owner(event, current_user_id) }
             .bind { |event| delete_event(event, current_user_id) }
      end

      private

      sig do
        params(event: Event, current_user_id: T.any(String, UUID))
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def delete_event(event, current_user_id)
        event_id = event.id
        workspace_id = event.workspace_id

        DB.transaction do
          DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "event", object_id: event_id)
          DB[:events].where(id: event_id).delete
          Broadcaster.object_deleted("event", event_id, workspace_id: workspace_id)
        end

        AuditLog.record(
          user_id: current_user_id,
          action: "delete",
          object_type: "event",
          object_id: event_id,
          workspace_id: workspace_id
        )

        APP_LOGGER.info { "[Events::Delete] Event #{event_id} deleted from workspace #{workspace_id}" }
        T.cast(Success({ deleted: [{ objectType: "event", id: event_id.to_s }] }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
