# frozen_string_literal: true

module Attendances
  # Find-or-create the member attendance row behind a presence-side write —
  # chore assignments arriving with a legacy `user_id` parameter need an
  # attendance to reference (doc/attendances.md, containment contract). An
  # existing row is returned untouched — never bumped to going; a missing one
  # is created as `pending` ("on the roster, hasn't answered"), the same
  # shape the phase-8 backfill synthesizes.
  module EnsureMemberRow
    class << self
      def call(event:, user_id:, created_by_user_id:)
        Success()
          .bind { Subjects.validate(event: event, user_id: user_id) }
          .bind { find_or_create(event, user_id, created_by_user_id) }
      end

      private

      def find_or_create(event, user_id, created_by_user_id)
        existing = Attendance.find_by_event_and_user(event.id, user_id)
        if existing
          Success(existing)
        else
          Success(create_pending_row(event, user_id, created_by_user_id))
        end
      end

      def create_pending_row(event, user_id, created_by_user_id)
        now = Time.now
        # DO NOTHING on conflict: a concurrent writer means the row exists —
        # re-read it instead of touching what they wrote.
        row = DB[:attendances]
              .returning(:id)
              .insert_conflict(
                target: %i[event_id user_id],
                conflict_where: Sequel.lit("user_id IS NOT NULL")
              )
              .insert(
                id: SecureRandom.uuid,
                event_id: event.id,
                user_id: user_id,
                guest_id: nil,
                host_user_id: nil,
                status: "pending",
                days: nil,
                created_by_user_id: created_by_user_id,
                created_at: now,
                updated_at: now
              )
              .first

        if row
          Broadcaster.object_changed("attendance", row[:id])
          Attendance.find(row[:id])
        else
          Attendance.find_by_event_and_user(event.id, user_id)
        end
      end
    end
  end
end
