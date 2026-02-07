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
        params(event_id: String, current_user_id: String)
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, current_user_id:)
        find_event(event_id)
          .bind { |event| authorize_owner(event, current_user_id) }
          .bind { |event| delete_event(event) }
      end

      private

      sig { params(event_id: String).returns(Result[Event, ServiceError]) }
      def find_event(event_id)
        event = Event.find(event_id)
        if event
          T.cast(Success(event), Result[Event, ServiceError])
        else
          T.cast(Failure(ServiceError.not_found("Event not found")), Result[Event, ServiceError])
        end
      end

      sig { params(event: Event, current_user_id: String).returns(Result[Event, ServiceError]) }
      def authorize_owner(event, current_user_id)
        if event.user_id == current_user_id
          T.cast(Success(event), Result[Event, ServiceError])
        else
          T.cast(Failure(ServiceError.forbidden("Access denied")), Result[Event, ServiceError])
        end
      end

      sig { params(event: Event).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def delete_event(event)
        event_id = event.id
        DB[:events].where(id: event_id).delete
        T.cast(Success({ deleted: [{ objectType: "event", id: event_id }] }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
