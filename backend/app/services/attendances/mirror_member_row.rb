# frozen_string_literal: true

module Attendances
  # Phase-2 dual-write (doc/attendances.md): writes the member-attendance
  # equivalent of an rsvp so later phases can move readers off rsvps without
  # divergence. Runs inside the caller's transaction and cannot fail — the
  # calling service has already validated everything. Retired with the rest
  # of the rsvp write path in phase 7.
  module MirrorMemberRow
    class << self
      def call(event:, user_id:, attending:, dates:, created_by_user_id:, now: Time.now)
        status = attending ? "going" : "declined"
        days = attending ? Attendances.normalize_days(event, dates) : nil
        days_json = days && Sequel.pg_jsonb(days.map(&:iso8601))

        row = DB[:attendances]
              .returning(:id)
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
                id: SecureRandom.uuid,
                event_id: event.id,
                user_id: user_id,
                guest_id: nil,
                host_user_id: nil,
                status: status,
                days: days_json,
                created_by_user_id: created_by_user_id,
                created_at: now,
                updated_at: now
              )
              .first
        Broadcaster.object_changed("attendance", row[:id])
        row[:id]
      end
    end
  end
end
