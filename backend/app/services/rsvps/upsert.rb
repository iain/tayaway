# typed: true
# frozen_string_literal: true

module Rsvps
  # Service to create or update an RSVP for an event.
  #
  # @example
  #   result = Rsvps::Upsert.call(
  #     event_id: "event-uuid",
  #     user_id: "uuid",
  #     attending: true,
  #     start_date: "2026-03-10",
  #     end_date: "2026-03-12"
  #   )
  module Upsert
    UUID_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    private_constant :UUID_REGEX

    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event_id: T.any(String, UUID),
          user_id: T.any(String, UUID),
          attending: T.nilable(T::Boolean),
          start_date: T.nilable(String),
          end_date: T.nilable(String),
          rsvp_id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, user_id:, attending:, start_date: nil, end_date: nil, rsvp_id: nil)
        # Idempotent replay: if client provided an ID that already exists, return it
        if rsvp_id
          existing = Rsvp.find(rsvp_id)
          if existing
            return T.cast(Success({ rsvp_id: existing.id, created: false }), Result[T::Hash[Symbol, T.untyped], ServiceError])
          end
        end

        validate_params(attending, rsvp_id)
          .bind { find_event(event_id) }
          .bind { |event| validate_event_has_dates(event) }
          .bind { |event| validate_event_not_in_past(event) }
          .bind { |event| validate_partial_dates(event, attending, start_date, end_date) }
          .bind { |event, parsed_start, parsed_end| upsert_rsvp(event, user_id, T.must(attending), parsed_start, parsed_end, rsvp_id) }
      end

      private

      sig do
        params(
          attending: T.nilable(T::Boolean),
          rsvp_id: T.nilable(String)
        ).returns(Result[T::Boolean, ServiceError])
      end
      def validate_params(attending, rsvp_id)
        if attending.nil?
          T.cast(Failure(ServiceError.validation("attending is required")), Result[T::Boolean, ServiceError])
        elsif rsvp_id && !UUID_REGEX.match?(rsvp_id)
          T.cast(Failure(ServiceError.validation("Invalid RSVP ID format")), Result[T::Boolean, ServiceError])
        else
          T.cast(Success(attending), Result[T::Boolean, ServiceError])
        end
      end

      sig { params(event_id: T.any(String, UUID)).returns(Result[Event, ServiceError]) }
      def find_event(event_id)
        event = Event.find(event_id)
        if event
          T.cast(Success(event), Result[Event, ServiceError])
        else
          T.cast(Failure(ServiceError.not_found("Event not found")), Result[Event, ServiceError])
        end
      end

      sig { params(event: Event).returns(Result[Event, ServiceError]) }
      def validate_event_has_dates(event)
        if event.start_date && event.end_date
          T.cast(Success(event), Result[Event, ServiceError])
        else
          T.cast(Failure(ServiceError.validation("Event does not have dates set")), Result[Event, ServiceError])
        end
      end

      sig { params(event: Event).returns(Result[Event, ServiceError]) }
      def validate_event_not_in_past(event)
        if T.must(event.end_date) < Date.today
          T.cast(Failure(ServiceError.validation("Cannot RSVP to an event that has already ended")), Result[Event, ServiceError])
        else
          T.cast(Success(event), Result[Event, ServiceError])
        end
      end

      sig do
        params(
          event: Event,
          attending: T.nilable(T::Boolean),
          start_date: T.nilable(String),
          end_date: T.nilable(String)
        ).returns(Result[T::Array[T.untyped], ServiceError])
      end
      def validate_partial_dates(event, attending, start_date, end_date)
        # Not attending or no partial dates specified — pass through
        unless attending && (start_date || end_date)
          return T.cast(Success([event, nil, nil]), Result[T::Array[T.untyped], ServiceError])
        end

        # Both must be provided
        if start_date.nil? || end_date.nil?
          return T.cast(
            Failure(ServiceError.validation("Both start_date and end_date are required for partial attendance")),
            Result[T::Array[T.untyped], ServiceError]
          )
        end

        begin
          parsed_start = Date.parse(start_date)
          parsed_end = Date.parse(end_date)
        rescue Date::Error
          return T.cast(
            Failure(ServiceError.validation("Invalid date format")),
            Result[T::Array[T.untyped], ServiceError]
          )
        end

        if parsed_start > parsed_end
          return T.cast(
            Failure(ServiceError.validation("start_date must be before or equal to end_date")),
            Result[T::Array[T.untyped], ServiceError]
          )
        end

        event_start = T.must(event.start_date)
        event_end = T.must(event.end_date)

        if parsed_start < event_start || parsed_end > event_end
          return T.cast(
            Failure(ServiceError.validation("Partial dates must fall within the event date range")),
            Result[T::Array[T.untyped], ServiceError]
          )
        end

        T.cast(Success([event, parsed_start, parsed_end]), Result[T::Array[T.untyped], ServiceError])
      end

      sig do
        params(
          event: Event,
          user_id: T.any(String, UUID),
          attending: T::Boolean,
          start_date: T.nilable(Date),
          end_date: T.nilable(Date),
          rsvp_id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def upsert_rsvp(event, user_id, attending, start_date, end_date, rsvp_id)
        existing_rsvp = Rsvp.find_by_event_and_user(event.id, user_id)
        result_rsvp_id = T.let(nil, T.nilable(T.any(String, UUID)))
        created = T.let(false, T::Boolean)

        # Clear partial dates if not attending
        unless attending
          start_date = nil
          end_date = nil
        end

        DB.transaction do
          now = Time.now

          if existing_rsvp
            DB[:rsvps].where(id: existing_rsvp.id).update(
              attending: attending,
              start_date: start_date,
              end_date: end_date,
              updated_at: now
            )
            result_rsvp_id = existing_rsvp.id
            created = false
          else
            result_rsvp_id = rsvp_id || SecureRandom.uuid

            DB[:rsvps].insert(
              id: result_rsvp_id,
              event_id: event.id,
              user_id: user_id,
              attending: attending,
              start_date: start_date,
              end_date: end_date,
              created_at: now,
              updated_at: now
            )
            created = true
          end

          Broadcaster.object_changed("rsvp", T.must(result_rsvp_id), workspace_id: event.workspace_id)
        end

        T.cast(Success({ rsvp_id: result_rsvp_id, created: created }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
    end
  end
end
