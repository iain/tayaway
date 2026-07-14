# frozen_string_literal: true

module Attendances
  # Idempotent converter from rsvps to attendances (doc/attendances.md,
  # migration staging phase 2; re-run once at the phase-4 cutover to catch
  # the edit gap). Member rows mirror 1:1; embedded per-day plus-one counts
  # synthesize placeholder guests deterministically: an event's max
  # concurrent count for a host becomes N guests ("Guest 1 (host)", …),
  # guest k attending the days where the count is at least k.
  #
  # Idempotency comes from deterministic row ids keyed on (event, host, k) —
  # re-runs update the same rows. The converter touches only
  # placeholder-flagged guests: once somebody renames one into a real
  # person, both the guest and their attendance are left alone. Run manually
  # via `rake attendances:backfill` (mise task of the same name).
  module Backfill
    class << self
      def call(now: Time.now)
        stats = Hash.new(0)
        # Events with attendances but no rsvps still need the stale sweep:
        # if every rsvp was deleted since the last run, the placeholders it
        # synthesized must flip to declined.
        event_ids = DB[:rsvps].distinct.select_map(:event_id) | DB[:attendances].distinct.select_map(:event_id)
        event_ids.each do |event_id|
          event = Event.find(event_id)
          next unless event

          DB.transaction { convert_event(event, stats, now) }
        end
        stats
      end

      private

      def convert_event(event, stats, now)
        rsvps = Rsvp.for_event(event.id)
        active_guest_ids = []

        rsvps.each do |rsvp|
          MirrorMemberRow.call(
            event: event,
            user_id: rsvp.user_id.to_s,
            attending: rsvp.attending,
            dates: rsvp.attendance&.map { |day| day[:date] } || legacy_range(rsvp),
            created_by_user_id: rsvp.created_by_user_id&.to_s,
            now: now
          )
          stats[:member_rows] += 1
          active_guest_ids.concat(convert_plus_ones(event, rsvp, stats, now))
        end

        decline_stale_placeholders(event, active_guest_ids, stats, now)
      end

      def legacy_range(rsvp)
        if rsvp.start_date && rsvp.end_date
          (rsvp.start_date..rsvp.end_date).to_a
        end
      end

      # Returns the deterministic guest ids this rsvp's counts support, after
      # upserting each guest and their going attendance.
      def convert_plus_ones(event, rsvp, stats, now)
        host_id = rsvp.user_id.to_s
        day_counts = {}
        if rsvp.attending && rsvp.attendance
          rsvp.attendance.each do |day|
            day_counts[day[:date]] = day[:plus_ones] if day[:plus_ones].positive?
          end
        end

        max_count = day_counts.values.max || 0
        return [] if max_count.zero?

        host_name = DB[:users].where(id: host_id).get(:name)
        (1..max_count).map do |k|
          days = day_counts.select { |_date, count| count >= k }.keys
          upsert_placeholder_guest(event, host_id, host_name, k, days, stats, now)
        end
      end

      def upsert_placeholder_guest(event, host_id, host_name, ordinal, days, stats, now)
        guest_id = deterministic_uuid("guest", event.id.to_s, host_id, ordinal)
        existing = DB[:guests].where(id: guest_id).first

        if existing.nil?
          DB[:guests].insert(
            id: guest_id,
            workspace_id: event.workspace_id,
            name: "Guest #{ordinal} (#{host_name})",
            placeholder: true,
            created_by_user_id: nil,
            created_at: now,
            updated_at: now
          )
          Broadcaster.object_changed("guest", guest_id)
          stats[:guests_created] += 1
        elsif !existing[:placeholder]
          # Renamed into a real person — leave the guest and their attendance
          # alone; they still count as active so the stale sweep skips them.
          return guest_id
        end

        days = Attendances.normalize_days(event, days)
        row = DB[:attendances]
              .returning(:id)
              .insert_conflict(
                target: %i[event_id guest_id],
                conflict_where: Sequel.lit("guest_id IS NOT NULL"),
                update: {
                  status: Sequel[:excluded][:status],
                  days: Sequel[:excluded][:days],
                  updated_at: Sequel[:excluded][:updated_at]
                }
              )
              .insert(
                id: deterministic_uuid("attendance", event.id.to_s, guest_id),
                event_id: event.id,
                user_id: nil,
                guest_id: guest_id,
                host_user_id: host_id,
                status: "going",
                days: days && Sequel.pg_jsonb(days.map(&:iso8601)),
                created_by_user_id: nil,
                created_at: now,
                updated_at: now
              )
              .first
        Broadcaster.object_changed("attendance", row[:id])
        stats[:guest_attendances] += 1
        guest_id
      end

      # Event-wide sweep: any going placeholder attendance the current counts
      # no longer support flips to declined — including guests whose host's
      # rsvp was deleted since the last run. Real (renamed) guests are never
      # touched.
      def decline_stale_placeholders(event, active_guest_ids, stats, now)
        stale_ids = DB[:attendances]
                    .join(:guests, id: :guest_id)
                    .where(
                      Sequel[:attendances][:event_id] => event.id,
                      Sequel[:attendances][:status] => "going",
                      Sequel[:guests][:placeholder] => true
                    )
                    .exclude(Sequel[:attendances][:guest_id] => active_guest_ids)
                    .select_map(Sequel[:attendances][:id])

        stale_ids.each do |id|
          DB[:attendances].where(id: id).update(status: "declined", days: nil, updated_at: now)
          Broadcaster.object_changed("attendance", id)
          stats[:guests_declined] += 1
        end
      end

      # Stable ids keyed on the conversion inputs make re-runs land on the
      # same rows instead of minting new ones.
      def deterministic_uuid(*parts)
        hex = Digest::SHA1.hexdigest(["attendances-backfill", *parts].join(":"))[0, 32]
        "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
      end
    end
  end
end
