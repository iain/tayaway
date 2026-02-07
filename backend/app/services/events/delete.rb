# typed: true
# frozen_string_literal: true

module Events
  # Service to delete an event.
  #
  # @example
  #   result = Events::Delete.call(event: event, current_user_id: "uuid")
  #   result.success?  # => true
  #   result.value!    # => { message: "Event deleted successfully" }
  module Delete
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(event: Event, current_user_id: String)
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event:, current_user_id:)
        authorize_owner(event, current_user_id).bind { |evt| delete_event(evt) }
      end

      private

      sig { params(event: Event, current_user_id: String).returns(Result[Event, ServiceError]) }
      def authorize_owner(event, current_user_id)
        if event.user_id == current_user_id
          Success(event)
        else
          Failure(ServiceError.forbidden("Access denied"))
        end
      end

      sig { params(event: Event).returns(Result[T::Hash[Symbol, T.untyped], ServiceError]) }
      def delete_event(event)
        event_id = event.id
        event.destroy
        Success({ deleted: [{ objectType: "event", id: event_id }] })
      end
    end
  end
end
