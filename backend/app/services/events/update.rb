# typed: true
# frozen_string_literal: true

module Events
  # Service to update an existing event.
  #
  # @example
  #   result = Events::Update.call(
  #     event_id: "uuid",
  #     current_user_id: "uuid",
  #     name: "Updated Name",
  #     description: "Updated description"
  #   )
  #   result.success?  # => true
  #   result.value!    # => { objects: [...] }
  module Update
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          name: T.nilable(String),
          description: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, current_user_id:, name:, description:)
        Event.find_result(event_id)
             .bind { |event| Event.authorize_owner(event, current_user_id) }
             .bind { |event| validate_name_with_event(name, event) }
             .bind { |event| update_event(event, name, description) }
      end

      private

      sig { params(name: T.nilable(String), event: Event).returns(Result[Event, ServiceError]) }
      def validate_name_with_event(name, event)
        if name.nil? || name.empty?
          T.cast(Failure(ServiceError.validation("Name is required")), Result[Event, ServiceError])
        else
          T.cast(Success(event), Result[Event, ServiceError])
        end
      end

      sig do
        params(
          event: Event,
          name: T.nilable(String),
          description: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_event(event, name, description)
        event_id = event.id
        workspace_id = event.workspace_id

        DB.transaction do
          DB[:events].where(id: event_id).update(
            name: name,
            description: description&.empty? ? nil : description,
            updated_at: Time.now
          )

          Broadcaster.object_changed("event", event_id, workspace_id: workspace_id)
        end

        updated_event = T.must(Event.find(event_id))
        PoolSerializer.event_result(updated_event)
      end
    end
  end
end
