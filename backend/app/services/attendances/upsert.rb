# frozen_string_literal: true

module Attendances
  # Create or update an attendance — the single write path for member and
  # guest rows alike (doc/attendances.md). RSVP is the action of calling
  # this; attendance is the stored answer.
  #
  # `membership` is the actor. The subject is exactly one of:
  #   user_id:  a workspace member
  #   guest_id: an existing workspace guest
  #   guest:    an inline `{ id:, name: }` payload — creates the guest in the
  #             same transaction when the (client-generated) id is new, so a
  #             new-guest-plus-attendance flow is one idempotent command.
  #
  # Rows conflict on the partial unique indexes (one row per person per
  # event): re-upserting keeps the existing row's id and original filer, and
  # re-adding a removed guest flips their declined row back to going.
  module Upsert
    STATUSES = %w[pending going declined].freeze

    class << self
      include LengthValidation

      def call(event_id:, membership:, attendance_id:, status:, user_id: nil, guest_id: nil, guest: nil, days: nil, host_user_id: nil)
        # Generate a server-side ID if the client did not provide one.
        resolved_id = attendance_id.nil? || attendance_id.empty? ? SecureRandom.uuid : attendance_id

        Auditable.around(
          service: "Attendances::Upsert",
          actor: membership,
          subject_type: "attendance",
          subject_id: resolved_id,
          context: {
            status: status,
            subject_user_id: user_id,
            subject_guest_id: guest_id || (guest && (guest["id"] || guest[:id]))
          }
        ) do
          Success()
            .bind { validate_status(status) }
            .bind { validate_subject_params(user_id, guest_id, guest) }
            .bind { find_event(event_id) }
            .bind { |event| EventPolicy.enforce(:create_attendance, event, membership: membership) }
            .bind { |event| validate_event_has_dates(event) }
            .bind { |event| resolve_subject(event, user_id, guest_id, guest) }
            .bind { |ctx| resolve_host(ctx, host_user_id, membership) }
            .bind { |ctx| validate_host_attending(ctx, status) }
            .bind { |ctx| validate_member_decline(ctx, status) }
            .bind { |ctx| resolve_days(ctx, status, days) }
            .bind { |ctx| upsert_attendance(ctx, status, resolved_id, membership.user_id) }
        end
      end

      private

      def validate_status(status)
        if status.nil? || status.to_s.empty?
          Failure(ServiceError.validation("status is required"))
        elsif !STATUSES.include?(status)
          Failure(ServiceError.validation("status must be one of pending, going, declined"))
        else
          Success()
        end
      end

      def validate_subject_params(user_id, guest_id, guest)
        member_given = given?(user_id)
        guest_given = given?(guest_id) || !guest.nil?

        if member_given && guest_given
          Failure(ServiceError.validation("Attendance subject must be either a member or a guest, not both"))
        elsif !member_given && !guest_given
          Failure(ServiceError.validation("user_id or guest is required"))
        elsif given?(guest_id) && !guest.nil?
          Failure(ServiceError.validation("guest_id and guest are mutually exclusive"))
        else
          Success()
        end
      end

      def given?(value)
        !(value.nil? || value.to_s.empty?)
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

      # Resolves the subject into `{ event:, subject: }` where subject is
      # `{ kind: :member, user_id: }` or `{ kind: :guest, guest_id:, create: }`
      # (`create` carries the name when the inline guest doesn't exist yet).
      def resolve_subject(event, user_id, guest_id, guest)
        if given?(user_id)
          Subjects.validate(event: event, user_id: user_id)
                  .bind { Success({ event: event, subject: { kind: :member, user_id: user_id } }) }
        elsif guest
          resolve_inline_guest(event, guest)
        else
          Guest.find_result(guest_id)
               .bind { |g| validate_guest_workspace(event, g) }
               .bind { |g| Success({ event: event, subject: { kind: :guest, guest_id: g.id.to_s } }) }
        end
      end

      def resolve_inline_guest(event, guest)
        payload_id = guest["id"] || guest[:id]
        resolved_guest_id = given?(payload_id) ? payload_id : SecureRandom.uuid
        existing = Guest.find(resolved_guest_id)

        if existing
          # Replay or race of an already-created guest: keep the stored name —
          # renames go through Guests::Rename, never through an upsert replay.
          validate_guest_workspace(event, existing)
            .bind { Success({ event: event, subject: { kind: :guest, guest_id: existing.id.to_s } }) }
        else
          name = (guest["name"] || guest[:name])&.strip
          validate_length(name, max: ValidationLimits::SHORT_STRING, field: "Name", required: true)
            .bind { Success({ event: event, subject: { kind: :guest, guest_id: resolved_guest_id, create: { name: name } } }) }
        end
      end

      def validate_guest_workspace(event, guest)
        if guest.workspace_id.to_s == event.workspace_id.to_s
          Success(guest)
        else
          Failure(ServiceError.validation("Guest is not part of this workspace"))
        end
      end

      # Guest rows are billed to a hosting member: an explicit host must be a
      # workspace member; otherwise the actor hosts. `host_explicit` decides
      # whether an upsert onto an existing row may reassign hostship — an
      # implicit default must never steal the guest from their current host.
      def resolve_host(ctx, host_user_id, membership)
        if ctx[:subject][:kind] != :guest
          Success(ctx)
        elsif !given?(host_user_id)
          Success(ctx.merge(host: membership.user_id.to_s, host_explicit: false))
        elsif WorkspaceMembership.find_by_workspace_and_user(ctx[:event].workspace_id, host_user_id)
          Success(ctx.merge(host: host_user_id, host_explicit: true))
        else
          Failure(ServiceError.validation("Host is not a member of this workspace"))
        end
      end

      # The decline guard below refuses to strand going guests on an absent
      # host; this is the same invariant from the other direction — a guest
      # cannot be marked going under a host who has already declined. Pending
      # (or unanswered) hosts don't block: undecided is not absent, and a date
      # reset parks everyone at pending. Nor do non-going guest transitions —
      # parking or removing a guest must always work.
      def validate_host_attending(ctx, status)
        if ctx[:subject][:kind] == :guest && status == "going" &&
           DB[:attendances].where(event_id: ctx[:event].id, user_id: ctx[:host], status: "declined").count > 0
          Failure(ServiceError.forbidden("The host is marked as not attending this event"))
        else
          Success(ctx)
        end
      end

      def validate_member_decline(ctx, status)
        subject = ctx[:subject]
        if subject[:kind] == :member && status == "declined"
          if DB[:expenses].where(event_id: ctx[:event].id, user_id: subject[:user_id]).count > 0
            Failure(ServiceError.forbidden("You cannot decline while you have expenses on this event"))
          elsif DB[:attendances].where(event_id: ctx[:event].id, host_user_id: subject[:user_id], status: "going").exclude(guest_id: nil).count > 0
            # Their guests would keep billing a host who isn't coming. Pending
            # guests don't block — they aren't counted anywhere.
            Failure(ServiceError.forbidden("You cannot decline while you have guests going on this event"))
          else
            Success(ctx)
          end
        else
          Success(ctx)
        end
      end

      # Days carry meaning only when going; otherwise they are stored NULL.
      # A full-coverage or empty day set normalizes to NULL ("whole event"),
      # mirroring Rsvps::Upsert.
      def resolve_days(ctx, status, days)
        if status != "going" || days.nil?
          Success(ctx.merge(days: nil))
        elsif !days.is_a?(Array)
          Failure(ServiceError.validation("days must be a list of dates"))
        else
          parse_days(ctx, days)
        end
      end

      def parse_days(ctx, days)
        event = ctx[:event]
        begin
          parsed = days.map { |day| Date.parse(day.to_s) }.uniq.sort
        rescue Date::Error, TypeError
          return Failure(ServiceError.validation("Invalid date format"))
        end

        if parsed.empty? || parsed == (event.start_date..event.end_date).to_a
          Success(ctx.merge(days: nil))
        elsif parsed.first < event.start_date || parsed.last > event.end_date
          Failure(ServiceError.validation("Days must fall within the event date range"))
        else
          Success(ctx.merge(days: parsed))
        end
      end

      def upsert_attendance(ctx, status, attendance_id, actor_user_id)
        days_json = ctx[:days] && Sequel.pg_jsonb(ctx[:days].map(&:iso8601))

        row = nil
        created_guest = nil
        DB.transaction do
          now = Time.now
          created_guest = create_inline_guest(ctx, actor_user_id, now)
          row = if ctx[:subject][:kind] == :member
                  upsert_member_row(ctx, status, days_json, attendance_id, actor_user_id, now)
                else
                  upsert_guest_row(ctx, status, days_json, attendance_id, actor_user_id, now)
                end
          Broadcaster.object_changed("attendance", row[:id])
        end

        Success({
          attendance_id: row[:id],
          created: row[:created],
          guest_id: ctx[:subject][:kind] == :guest ? ctx[:subject][:guest_id] : nil,
          guest_created: !created_guest.nil?
        }
               )
      end

      # Returns the inserted guest row, or nil when nothing was created
      # (member subject, existing guest, or an idempotent replay).
      def create_inline_guest(ctx, actor_user_id, now)
        subject = ctx[:subject]
        return nil unless subject[:kind] == :guest && subject[:create]

        # DO NOTHING on id conflict: a replay must not resurrect a name the
        # guest has since been renamed to.
        created = DB[:guests]
                  .returning(:id)
                  .insert_conflict(target: :id)
                  .insert(
                    id: subject[:guest_id],
                    workspace_id: ctx[:event].workspace_id,
                    name: subject[:create][:name],
                    placeholder: false,
                    created_by_user_id: actor_user_id,
                    created_at: now,
                    updated_at: now
                  )
                  .first

        Broadcaster.object_changed("guest", subject[:guest_id]) if created
        created
      end

      # `created_by_user_id` is intentionally absent from both conflict
      # updates so the original filer sticks even if a different actor later
      # edits (same as Rsvps::Upsert).
      def upsert_member_row(ctx, status, days_json, attendance_id, actor_user_id, now)
        DB[:attendances]
          .returning(:id, Sequel.lit("(xmax = 0) AS created"))
          .insert_conflict(
            target: %i[event_id user_id],
            conflict_where: Sequel.lit("user_id IS NOT NULL"),
            update: {
              status: Sequel[:excluded][:status],
              days: Sequel[:excluded][:days],
              updated_at: Sequel[:excluded][:updated_at]
            }
          )
          .insert(
            id: attendance_id,
            event_id: ctx[:event].id,
            user_id: ctx[:subject][:user_id],
            guest_id: nil,
            host_user_id: nil,
            status: status,
            days: days_json,
            created_by_user_id: actor_user_id,
            created_at: now,
            updated_at: now
          )
          .first
      end

      def upsert_guest_row(ctx, status, days_json, attendance_id, actor_user_id, now)
        update = {
          status: Sequel[:excluded][:status],
          days: Sequel[:excluded][:days],
          updated_at: Sequel[:excluded][:updated_at]
        }
        # Only an explicitly passed host may reassign hostship on an existing
        # row; the implicit actor default applies to fresh inserts only.
        update[:host_user_id] = Sequel[:excluded][:host_user_id] if ctx[:host_explicit]

        DB[:attendances]
          .returning(:id, Sequel.lit("(xmax = 0) AS created"))
          .insert_conflict(
            target: %i[event_id guest_id],
            conflict_where: Sequel.lit("guest_id IS NOT NULL"),
            update: update
          )
          .insert(
            id: attendance_id,
            event_id: ctx[:event].id,
            user_id: nil,
            guest_id: ctx[:subject][:guest_id],
            host_user_id: ctx[:host],
            status: status,
            days: days_json,
            created_by_user_id: actor_user_id,
            created_at: now,
            updated_at: now
          )
          .first
      end
    end
  end
end
