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
          description: T.nilable(String),
          start_date: T.nilable(String),
          end_date: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, current_user_id:, name:, description:, start_date: nil, end_date: nil)
        Event.find_result(event_id)
             .bind { |event| Event.authorize_owner(event, current_user_id) }
             .bind { |event| validate_name_with_event(name, event) }
             .bind { |event| validate_dates(start_date, end_date).fmap { |dates| [event, dates] } }
             .bind { |(event, dates)| update_event(event, name, description, dates) }
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
          event: Event,
          name: T.nilable(String),
          description: T.nilable(String),
          dates: T.nilable(T::Array[Date])
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_event(event, name, description, dates)
        event_id = event.id
        workspace_id = event.workspace_id

        DB.transaction do
          update_data = {
            name: name,
            description: description&.empty? ? nil : description,
            updated_at: Time.now
          }

          if dates
            update_data[:start_date] = dates[0]
            update_data[:end_date] = dates[1]
          end

          DB[:events].where(id: event_id).update(update_data)

          Broadcaster.object_changed("event", event_id, workspace_id: workspace_id)
        end

        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_event(T.must(Event.find(event_id)))
        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
