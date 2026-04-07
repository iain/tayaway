# frozen_string_literal: true

module Rsvps
  # Service to create or update an RSVP for an event.
  #
  # @example
  #   result = Rsvps::Upsert.call(
  #     event_id: "event-uuid",
  #     user_id: "uuid",
  #     attending: true,
  #     rsvp_id: "client-generated-uuid",
  #     start_date: "2026-03-10",
  #     end_date: "2026-03-12"
  #   )
  module Upsert
    class << self
      include Dry::Monads[:result]

      def call(event_id:, user_id:, attending:, rsvp_id:, start_date: nil, end_date: nil)
        # Idempotent replay: if client provided an ID that already exists, return it
        if rsvp_id
          existing = Rsvp.find(rsvp_id)
          if existing
            return Success({ rsvp_id: existing.id, created: false })
          end
        end

        # Generate a server-side ID if the client did not provide one (backwards
        # compatibility with commands queued before client-ID enforcement).
        resolved_rsvp_id = rsvp_id.nil? || rsvp_id.empty? ? SecureRandom.uuid : rsvp_id

        validate_params(attending)
          .bind { find_event(event_id) }
          .bind { |event| validate_event_has_dates(event) }
          .bind { |event| validate_no_expenses_when_declining(event, user_id, attending) }
          .bind { |event| validate_partial_dates(event, attending, start_date, end_date) }
          .bind { |event, parsed_start, parsed_end| upsert_rsvp(event, user_id, attending, parsed_start, parsed_end, resolved_rsvp_id) }
      end

      private

      def validate_params(attending)
        if attending.nil?
          Failure(ServiceError.validation("attending is required"))
        else
          Success(attending)
        end
      end

      def find_event(event_id)
        event = Event.find(event_id)
        if event
          Success(event)
        else
          Failure(ServiceError.not_found("Event not found"))
        end
      end

      def validate_event_has_dates(event)
        if event.start_date && event.end_date
          Success(event)
        else
          Failure(ServiceError.validation("Event does not have dates set"))
        end
      end

      def validate_no_expenses_when_declining(event, user_id, attending)
        if !attending && DB[:expenses].where(event_id: event.id, user_id: user_id).count > 0
          return Failure(ServiceError.forbidden("You cannot decline while you have expenses on this event"))
        end

        Success(event)
      end

      def validate_partial_dates(event, attending, start_date, end_date)
        # Not attending or no partial dates specified — pass through
        unless attending && (start_date || end_date)
          return Success([event, nil, nil])
        end

        # Both must be provided
        if start_date.nil? || end_date.nil?
          return Failure(ServiceError.validation("Both start_date and end_date are required for partial attendance"))
        end

        begin
          parsed_start = Date.parse(start_date)
          parsed_end = Date.parse(end_date)
        rescue Date::Error
          return Failure(ServiceError.validation("Invalid date format"))
        end

        if parsed_start > parsed_end
          return Failure(ServiceError.validation("start_date must be before or equal to end_date"))
        end

        event_start = event.start_date
        event_end = event.end_date

        if parsed_start < event_start || parsed_end > event_end
          return Failure(ServiceError.validation("Partial dates must fall within the event date range"))
        end

        Success([event, parsed_start, parsed_end])
      end

      def upsert_rsvp(event, user_id, attending, start_date, end_date, rsvp_id)
        existing_rsvp = Rsvp.find_by_event_and_user(event.id, user_id)
        result_rsvp_id = nil
        created = false

        # Clear partial dates if not attending
        unless attending
          start_date = nil
          end_date = nil
        end

        begin
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
              result_rsvp_id = rsvp_id

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

            Broadcaster.object_changed("rsvp", result_rsvp_id, workspace_id: event.workspace_id)
          end
        rescue Sequel::UniqueConstraintViolation
          existing = Rsvp.find_by_event_and_user(event.id, user_id)
          result_rsvp_id = existing.id
          created = false
          Broadcaster.object_changed("rsvp", result_rsvp_id, workspace_id: event.workspace_id)
        end

        Success({ rsvp_id: result_rsvp_id, created: created })
      end
    end
  end
end
