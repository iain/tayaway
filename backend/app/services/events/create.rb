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
          id: T.nilable(String),
          start_date: T.nilable(String),
          end_date: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(workspace_id:, user_id:, name:, description:, id: nil, start_date: nil, end_date: nil)
        validate_name(name)
          .bind { |valid_name| validate_dates(start_date, end_date).fmap { |dates| [valid_name, dates] } }
          .bind { |(valid_name, dates)| create_event(workspace_id, user_id, valid_name, description, id, dates) }
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
          start_date: T.nilable(String),
          end_date: T.nilable(String)
        ).returns(Result[T.nilable(T::Array[Date]), ServiceError])
      end
      def validate_dates(start_date, end_date)
        return T.cast(Success(nil), Result[T.nilable(T::Array[Date]), ServiceError]) if start_date.nil? && end_date.nil?

        if start_date.nil? || end_date.nil?
          return T.cast(
            Failure(ServiceError.validation("Both start date and end date must be provided")),
            Result[T.nilable(T::Array[Date]), ServiceError]
          )
        end

        parsed_start = Date.parse(start_date)
        parsed_end = Date.parse(end_date)

        if parsed_start > parsed_end
          return T.cast(
            Failure(ServiceError.validation("Start date must be before or equal to end date")),
            Result[T.nilable(T::Array[Date]), ServiceError]
          )
        end

        T.cast(Success([parsed_start, parsed_end]), Result[T.nilable(T::Array[Date]), ServiceError])
      rescue Date::Error
        T.cast(
          Failure(ServiceError.validation("Invalid date format")),
          Result[T.nilable(T::Array[Date]), ServiceError]
        )
      end

      sig do
        params(
          workspace_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          name: String,
          description: T.nilable(String),
          id: T.nilable(String),
          dates: T.nilable(T::Array[Date])
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_event(workspace_id, user_id, name, description, id, dates)
        # Idempotent replay: if client provided an ID and it already exists, return it
        if id
          existing = Event.find(id)
          if existing
            pool = PoolSerializer.new(workspace_id: workspace_id)
            pool.add_event(existing)
            return T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
          end
        end

        event = DB.transaction do
          now = Time.now
          event_id = id || SecureRandom.uuid

          insert_data = {
            id: event_id,
            workspace_id: workspace_id,
            user_id: user_id,
            name: name,
            description: description&.empty? ? nil : description,
            created_at: now,
            updated_at: now
          }

          if dates
            insert_data[:start_date] = dates[0]
            insert_data[:end_date] = dates[1]
          end

          DB[:events].insert(insert_data)

          Broadcaster.object_changed("event", event_id, workspace_id: workspace_id)

          Event.find(event_id)
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_event(event)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
