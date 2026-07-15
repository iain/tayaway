# frozen_string_literal: true

module DatePolls
  # Service to close a date poll by selecting a winning date range.
  module Close
    class << self
      def call(event_id:, membership:, selected_date_range_id:)
        Auditable.around(
          service: "DatePolls::Close",
          actor: membership,
          subject_type: "date_poll",
          context: { selected_date_range_id: selected_date_range_id }
        ) do
          Success()
            .bind { Event.find_result(event_id) }
            .bind { |event| DatePoll.find_by_event_result(event.id).fmap { |poll| [event, poll] } }
            .bind { |(event, poll)| DatePollPolicy.enforce(:close, poll, membership: membership, event: event).fmap { |_| [event, poll] } }
            .bind { |(event, poll)| validate_not_resolved(event, poll) }
            .bind { |(event, poll)| validate_date_range(event, poll, selected_date_range_id) }
            .bind { |(event, poll, dr_id)| close_poll(event, poll, dr_id, membership) }
        end
      end

      private

      def validate_not_resolved(event, poll)
        if poll.closed_at
          Failure(ServiceError.validation("Poll is already resolved"))
        else
          Success([event, poll])
        end
      end

      def validate_date_range(event, poll, selected_date_range_id)
        if selected_date_range_id.nil? || selected_date_range_id.empty?
          return Failure(ServiceError.validation("selected_date_range_id is required"))
        end

        date_range = DateRange.find(selected_date_range_id)
        unless date_range && date_range.date_poll_id == poll.id
          return Failure(ServiceError.validation("Date range does not belong to this poll"))
        end

        Success([event, poll, selected_date_range_id])
      end

      def close_poll(event, poll, selected_date_range_id, membership)
        date_range = DateRange.find(selected_date_range_id)
        yes_voter_ids = []

        DB.transaction do
          DB[:date_polls].where(id: poll.id).update(
            selected_date_range_id: selected_date_range_id,
            closed_at: Time.now
          )

          DB[:events].where(id: event.id).update(
            start_date: date_range.start_date,
            end_date: date_range.end_date
          )

          # Auto-RSVP "yes" voters on the winning date range as attending
          yes_voter_ids = DB[:votes]
                          .where(date_range_id: selected_date_range_id, response: "yes")
                          .select_map(:user_id)

          # The mirror normalizes day sets against the event's window, which
          # the update above just moved to the winning range.
          updated_event = event.with(start_date: date_range.start_date, end_date: date_range.end_date)

          now = Time.now
          yes_voter_ids.each do |uid|
            existing = DB[:rsvps].where(event_id: event.id, user_id: uid).first
            if existing
              DB[:rsvps].where(id: existing[:id]).update(attending: true, updated_at: now)
              Broadcaster.object_changed("rsvp", existing[:id])
            else
              rsvp_id = SecureRandom.uuid
              DB[:rsvps].insert(id: rsvp_id, event_id: event.id, user_id: uid, attending: true, created_at: now, updated_at: now)
              Broadcaster.object_changed("rsvp", rsvp_id)
            end
            # Phase-2 dual-write (doc/attendances.md): every rsvp write path
            # must mirror, or attendance-based readers (chore autofill) see
            # auto-RSVPed voters as absent. An existing rsvp keeps its day
            # set above, so the mirror must carry the same days — a nil here
            # would silently widen a partial-day answer to whole-event.
            Attendances::MirrorMemberRow.call(
              event: updated_event,
              user_id: uid,
              attending: true,
              dates: existing && mirror_dates(existing),
              created_by_user_id: nil,
              now: now
            )
          end

          Broadcaster.object_changed("date_poll", poll.id)
          Broadcaster.object_changed("event", event.id)
        end

        APP_LOGGER.info { "[DatePolls::Close] Poll #{poll.id} closed on event #{event.id} with date range #{selected_date_range_id}" }
        DatePolls::OnClosed.call(event: event, date_range: date_range, yes_voter_ids: yes_voter_ids)

        pool = PoolSerializer.new(membership: membership)
        pool.add(:event, [Event.find(event.id)])
        pool.add(:date_poll, [DatePoll.find(poll.id)])
        pool.add(:rsvp, Rsvp.for_event(event.id))
        Success({ objects: pool.to_a })
      end

      # The concrete day list an existing rsvp row carries: its attendance
      # day set when present, otherwise the legacy contiguous range — the
      # same resolution the backfill converter uses.
      def mirror_dates(row)
        rsvp = Rsvp.find(row[:id])
        if rsvp.attendance
          rsvp.attendance.map { |day| day[:date] }
        elsif rsvp.start_date && rsvp.end_date
          (rsvp.start_date..rsvp.end_date).to_a
        end
      end
    end
  end
end
