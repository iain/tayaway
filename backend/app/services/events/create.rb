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
      include Events::Validators

      sig do
        params(
          workspace_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          name: T.nilable(String),
          description: T.nilable(String),
          id: T.nilable(String),
          start_date: T.nilable(String),
          end_date: T.nilable(String),
          location_name: T.nilable(String),
          latitude: T.nilable(Float),
          longitude: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(workspace_id:, user_id:, name:, description:, id: nil, start_date: nil, end_date: nil,
               location_name: nil, latitude: nil, longitude: nil)
        validate_name(name)
          .bind { |valid_name| validate_text_lengths(description, location_name).fmap { valid_name } }
          .bind { |valid_name| validate_dates(start_date, end_date).fmap { |dates| [valid_name, dates] } }
          .bind do |(valid_name, dates)|
            create_event(
              workspace_id: workspace_id, user_id: user_id, name: valid_name,
              description: description, id: id, dates: dates,
              location_name: location_name, latitude: latitude, longitude: longitude
            )
          end
      end

      private

      sig { params(name: T.nilable(String)).returns(Result[String, ServiceError]) }
      def validate_name(name)
        if name.nil? || name.empty?
          T.cast(Failure(ServiceError.validation("Name is required")), Result[String, ServiceError])
        elsif name.length > ValidationLimits::SHORT_STRING
          T.cast(Failure(ServiceError.validation("Name is too long (maximum 255 characters)")), Result[String, ServiceError])
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
          dates: T.nilable(T::Array[Date]),
          location_name: T.nilable(String),
          latitude: T.nilable(Float),
          longitude: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def create_event(workspace_id:, user_id:, name:, description:, id:, dates:, location_name:, latitude:, longitude:)
        # Idempotent replay: if client provided an ID and it already exists, return it
        if id
          existing = Event.find(id)
          if existing
            pool = PoolSerializer.new(workspace_id: workspace_id)
            pool.add_event(existing)
            return T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
          end
        end

        event = begin
          DB.transaction do
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

            if location_name && !location_name.empty? && latitude && longitude
              insert_data[:location_name] = location_name
              insert_data[:location_coordinates] = Sequel.lit("point(?, ?)", longitude, latitude)
            end

            DB[:events].insert(insert_data)

            Broadcaster.object_changed("event", event_id, workspace_id: workspace_id)

            Event.find(event_id)
          end
        rescue Sequel::UniqueConstraintViolation
          T.must(Event.find(T.must(id)))
        end

        APP_LOGGER.info { "[Events::Create] User #{user_id} created event #{event.id} in workspace #{workspace_id}" }

        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_event(event)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
