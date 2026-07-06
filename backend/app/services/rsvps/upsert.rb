# frozen_string_literal: true

module Rsvps
  # Service to create or update an RSVP for an event.
  #
  # @example
  #   result = Rsvps::Upsert.call(
  #     event_id: "event-uuid",
  #     membership: membership,
  #     user_id: "subject-user-uuid",
  #     attending: true,
  #     rsvp_id: "client-generated-uuid",
  #     start_date: "2026-03-10",
  #     end_date: "2026-03-12"
  #   )
  #
  # `membership` is the actor (the user performing the action). `user_id` is
  # the subject (the user whose RSVP this is). They differ when one workspace
  # member is filling in or correcting another member's RSVP.
  module Upsert
    class << self
      def call(event_id:, membership:, user_id:, attending:, rsvp_id:, attendance: nil, start_date: nil, end_date: nil)
        # Generate a server-side ID if the client did not provide one (backwards
        # compatibility with commands queued before client-ID enforcement).
        resolved_rsvp_id = rsvp_id.nil? || rsvp_id.empty? ? SecureRandom.uuid : rsvp_id

        Auditable.around(
          service: "Rsvps::Upsert",
          actor: membership,
          subject_type: "rsvp",
          subject_id: resolved_rsvp_id,
          context: { attending: attending, subject_user_id: user_id }
        ) do
          Success()
            .bind { validate_params(attending, user_id) }
            .bind { find_event(event_id) }
            .bind { |event| EventPolicy.enforce(:create_rsvp, event, membership: membership) }
            .bind { |event| Subjects.validate(event: event, user_id: user_id) }
            .bind { |event| validate_event_has_dates(event) }
            .bind { |event| validate_no_expenses_when_declining(event, user_id, attending) }
            .bind { |event| resolve_attendance(event, attending, attendance, start_date, end_date) }
            .bind { |event, resolved| upsert_rsvp(event, user_id, attending, resolved, resolved_rsvp_id, membership.user_id) }
        end
      end

      private

      def validate_params(attending, user_id)
        if attending.nil?
          Failure(ServiceError.validation("attending is required"))
        elsif user_id.nil? || user_id.to_s.empty?
          Failure(ServiceError.validation("user_id is required"))
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

      # Resolve the requested attendance into concrete storage values:
      # `{ attendance: Array<Date> | nil, start_date: Date | nil, end_date: Date | nil }`.
      # A non-empty `attendance` day set (new "come and go" clients) is
      # authoritative; `start_date`/`end_date` remain a legacy contiguous-range
      # path. Either way we also persist the contiguous hull on start/end so old
      # code still reading the range keeps working during the deploy.
      # The canonical "attends the whole event" storage: no explicit day set and
      # no partial range.
      def whole_event
        { attendance: nil, start_date: nil, end_date: nil }
      end

      def resolve_attendance(event, attending, attendance, start_date, end_date)
        return Success([event, whole_event]) unless attending

        # Any non-nil `attendance` (including `[]`) is a day-set request; let
        # resolve_day_set own the array/emptiness validation.
        if attendance
          resolve_day_set(event, attendance)
        elsif start_date || end_date
          resolve_legacy_range(event, start_date, end_date)
        else
          Success([event, whole_event])
        end
      end

      def resolve_day_set(event, attendance)
        return Failure(ServiceError.validation("attendance must be a list of dates")) unless attendance.is_a?(Array)

        begin
          dates = attendance.map { |value| Date.parse(value.to_s) }.uniq.sort
        rescue Date::Error, TypeError
          return Failure(ServiceError.validation("Invalid date format"))
        end

        if dates.empty? || dates == (event.start_date..event.end_date).to_a
          # No restriction, or every day selected — store "whole event"
          # canonically as NULL so counts and displays treat it like a full RSVP.
          Success([event, whole_event])
        elsif dates.first < event.start_date || dates.last > event.end_date
          Failure(ServiceError.validation("Attendance dates must fall within the event date range"))
        else
          # `attendance` is the authoritative day set; keep the contiguous hull
          # on start/end for legacy readers.
          Success([event, { attendance: dates, start_date: dates.first, end_date: dates.last }])
        end
      end

      def resolve_legacy_range(event, start_date, end_date)
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
          Failure(ServiceError.validation("start_date must be before or equal to end_date"))
        elsif parsed_start < event.start_date || parsed_end > event.end_date
          Failure(ServiceError.validation("Partial dates must fall within the event date range"))
        else
          Success([event, { attendance: nil, start_date: parsed_start, end_date: parsed_end }])
        end
      end

      def upsert_rsvp(event, user_id, attending, resolved, rsvp_id, actor_user_id)
        attendance = resolved[:attendance]
        start_date = resolved[:start_date]
        end_date = resolved[:end_date]
        attendance_json = attendance ? Sequel.pg_jsonb(attendance.map(&:iso8601)) : nil

        row = nil
        DB.transaction do
          now = Time.now
          # `created_by_user_id` is intentionally absent from the conflict update
          # so the original filer sticks even if a different actor later edits.
          row = DB[:rsvps]
                .returning(:id, Sequel.lit("(xmax = 0) AS created"))
                .insert_conflict(
                  target: %i[event_id user_id],
                  update: {
                    attending: Sequel[:excluded][:attending],
                    attendance: Sequel[:excluded][:attendance],
                    start_date: Sequel[:excluded][:start_date],
                    end_date: Sequel[:excluded][:end_date],
                    updated_at: Sequel[:excluded][:updated_at]
                  }
                )
                .insert(
                  id: rsvp_id,
                  event_id: event.id,
                  user_id: user_id,
                  created_by_user_id: actor_user_id,
                  attending: attending,
                  attendance: attendance_json,
                  start_date: start_date,
                  end_date: end_date,
                  created_at: now,
                  updated_at: now
                )
                .first

          Broadcaster.object_changed("rsvp", row[:id])
        end

        Success({ rsvp_id: row[:id], created: row[:created] })
      end
    end
  end
end
