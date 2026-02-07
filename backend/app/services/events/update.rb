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
  #     description: "Updated description",
  #     date_ranges: [{ "start_date" => "2024-01-01", "end_date" => "2024-01-02" }]
  #   )
  #   result.success?  # => true
  #   result.value!    # => { event: {...} }
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
          date_ranges: T::Array[T::Hash[String, String]]
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, current_user_id:, name:, description:, date_ranges:)
        find_event(event_id)
          .bind { |event| authorize_owner(event, current_user_id) }
          .bind { |event| validate_name_with_event(name, event) }
          .bind { |event| update_event(event, name, description, date_ranges) }
      end

      private

      sig { params(event_id: T.any(String, UUID)).returns(Result[Event, ServiceError]) }
      def find_event(event_id)
        event = Event.find(event_id)
        if event
          T.cast(Success(event), Result[Event, ServiceError])
        else
          T.cast(Failure(ServiceError.not_found("Event not found")), Result[Event, ServiceError])
        end
      end

      sig { params(event: Event, current_user_id: T.any(String, UUID)).returns(Result[Event, ServiceError]) }
      def authorize_owner(event, current_user_id)
        if event.user_id == current_user_id
          T.cast(Success(event), Result[Event, ServiceError])
        else
          T.cast(Failure(ServiceError.forbidden("Access denied")), Result[Event, ServiceError])
        end
      end

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
          description: T.nilable(String),
          date_ranges: T::Array[T::Hash[String, String]]
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def update_event(event, name, description, date_ranges)
        event_id = event.id
        workspace_id = event.workspace_id

        updated_event = DB.transaction do
          DB[:events].where(id: event_id).update(
            name: name,
            description: description&.empty? ? nil : description,
            updated_at: Time.now
          )

          sync_date_ranges(event_id, date_ranges)

          Broadcaster.object_changed("event", event_id, workspace_id: workspace_id)

          Event.find(event_id)
        end

        pool = PoolSerializer.new
        pool.add_event(updated_event)

        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end

      sig do
        params(
          event_id: T.any(String, UUID),
          date_ranges: T::Array[T::Hash[String, String]]
        ).void
      end
      def sync_date_ranges(event_id, date_ranges)
        incoming = date_ranges.map do |dr|
          [Date.parse(dr["start_date"]), Date.parse(dr["end_date"])]
        end.to_set

        existing = DateRange.for_event(event_id).map do |dr|
          [[dr.start_date, dr.end_date], dr]
        end.to_h

        # Delete date ranges that are no longer in the incoming list
        existing.each do |(key, dr)|
          DB[:date_ranges].where(id: dr.id).delete unless incoming.include?(key)
        end

        # Create new date ranges that don't exist yet
        existing_keys = existing.keys.to_set
        incoming.each do |(start_date, end_date)|
          next if existing_keys.include?([start_date, end_date])

          now = Time.now
          DB[:date_ranges].insert(
            id: SecureRandom.uuid,
            event_id: event_id,
            start_date: start_date,
            end_date: end_date,
            created_at: now,
            updated_at: now
          )
        end
      end
    end
  end
end
