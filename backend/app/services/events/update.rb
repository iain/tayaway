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
      include Events::Validators

      sig do
        params(
          event_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          name: T.nilable(String),
          description: T.nilable(String),
          start_date: T.nilable(String),
          end_date: T.nilable(String),
          location_name: T.nilable(String),
          latitude: T.nilable(Float),
          longitude: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, current_user_id:, name:, description:, start_date: nil, end_date: nil,
               location_name: nil, latitude: nil, longitude: nil)
        Event.find_result(event_id)
             .bind { |event| EventPolicy.new(event: event, user_id: current_user_id.to_s).authorize!(:update, value: event) }
             .bind { |event| validate_name_with_event(name, event) }
             .bind { |event| validate_text_lengths(description, location_name).fmap { event } }
             .bind { |event| validate_coordinates(latitude, longitude).fmap { event } }
             .bind { |event| validate_dates(start_date, end_date).fmap { |dates| [event, dates] } }
             .bind { |(event, dates)| check_no_resolved_poll_when_clearing(event, dates).fmap { [event, dates] } }
             .bind do |(event, dates)|
               update_event(
                 event: event, current_user_id: current_user_id, name: name, description: description,
                 dates: dates, location_name: location_name, latitude: latitude, longitude: longitude
               )
             end
      end

      private

      sig { params(name: T.nilable(String), event: Event).returns(Result[Event, ServiceError]) }
      def validate_name_with_event(name, event)
        if name.nil? || name.empty?
          T.cast(Failure(ServiceError.validation("Name is required")), Result[Event, ServiceError])
        elsif name.length > ValidationLimits::SHORT_STRING
          T.cast(Failure(ServiceError.validation("Name is too long (maximum 255 characters)")), Result[Event, ServiceError])
        else
          T.cast(Success(event), Result[Event, ServiceError])
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

        # Both empty string — clear dates
        if (start_date.nil? || start_date.empty?) && (end_date.nil? || end_date.empty?)
          return T.cast(Success([]), Result[T.nilable(T::Array[Date]), ServiceError])
        end

        if start_date.nil? || start_date.empty? || end_date.nil? || end_date.empty?
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
          event: Event,
          dates: T.nilable(T::Array[Date])
        ).returns(Result[T.untyped, ServiceError])
      end
      def check_no_resolved_poll_when_clearing(event, dates)
        return T.cast(Success(nil), Result[T.untyped, ServiceError]) unless dates&.empty?

        poll = DatePoll.find_by_event(event.id)
        if poll&.closed_at
          T.cast(
            Failure(ServiceError.validation("Cannot clear dates while a resolved poll exists")),
            Result[T.untyped, ServiceError]
          )
        else
          T.cast(Success(nil), Result[T.untyped, ServiceError])
        end
      end

      sig do
        params(
          event: Event,
          current_user_id: T.any(String, UUID),
          name: T.nilable(String),
          description: T.nilable(String),
          dates: T.nilable(T::Array[Date]),
          location_name: T.nilable(String),
          latitude: T.nilable(Float),
          longitude: T.nilable(Float)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_event(event:, current_user_id:, name:, description:, dates:, location_name:, latitude:, longitude:)
        event_id = event.id
        workspace_id = event.workspace_id

        DB.transaction do
          update_data = {
            name: name,
            description: description&.empty? ? nil : description,
            updated_at: Time.now
          }

          if dates
            if dates.empty?
              update_data[:start_date] = nil
              update_data[:end_date] = nil
            else
              update_data[:start_date] = dates[0]
              update_data[:end_date] = dates[1]
            end
          end

          unless location_name.nil?
            if location_name.empty?
              update_data[:location_name] = nil
              update_data[:location_coordinates] = nil
            elsif latitude && longitude
              update_data[:location_name] = location_name
              update_data[:location_coordinates] = Sequel.lit("point(?, ?)", longitude, latitude)
            else
              update_data[:location_name] = location_name
              update_data[:location_coordinates] = nil
            end
          end

          DB[:events].where(id: event_id).update(update_data)

          Broadcaster.object_changed("event", event_id, workspace_id: workspace_id)
        end

        APP_LOGGER.info { "[Events::Update] Event #{event_id} updated in workspace #{workspace_id}" }

        pool = PoolSerializer.new(workspace_id: workspace_id, user_id: current_user_id.to_s)
        pool.add_event(T.must(Event.find(event_id)))
        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
