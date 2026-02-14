# typed: true
# frozen_string_literal: true

module Events
  # Service to create a new event.
  #
  # @example
  #   result = Events::Create.call(
  #     user_id: "uuid",
  #     name: "Team Meeting",
  #     description: "Weekly sync"
  #   )
  #   result.success?  # => true
  #   result.value!    # => { objects: [...] }
  module Create
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          workspace_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          name: T.nilable(String),
          description: T.nilable(String),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(workspace_id:, user_id:, name:, description:, id: nil)
        validate_name(name).bind { |valid_name| create_event(workspace_id, user_id, valid_name, description, id) }
      end

      private

      sig { params(name: T.nilable(String)).returns(Result[String, ServiceError]) }
      def validate_name(name)
        if name.nil? || name.empty?
          T.cast(Failure(ServiceError.validation("Name is required")), Result[String, ServiceError])
        else
          T.cast(Success(name), Result[String, ServiceError])
        end
      end

      sig do
        params(
          workspace_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          name: String,
          description: T.nilable(String),
          id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_event(workspace_id, user_id, name, description, id)
        # Idempotent replay: if client provided an ID and it already exists, return it
        if id
          existing = Event.find(id)
          if existing
            pool = PoolSerializer.new
            pool.add_event(existing)
            return T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
          end
        end

        event = DB.transaction do
          now = Time.now
          event_id = id || SecureRandom.uuid

          DB[:events].insert(
            id: event_id,
            workspace_id: workspace_id,
            user_id: user_id,
            name: name,
            description: description&.empty? ? nil : description,
            created_at: now,
            updated_at: now
          )

          Broadcaster.object_changed("event", event_id, workspace_id: workspace_id)

          Event.find(event_id)
        end

        pool = PoolSerializer.new
        pool.add_event(event)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
