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
            .bind { |(event, poll)| validate_date_range(event, poll, selected_date_range_id) }
            .bind { |(event, poll, dr_id)| close_poll(event, poll, dr_id, membership) }
        end
      end

      private

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
        reset = dates_changed?(event, date_range)
        # Resolved before the revert: the poll-closed notice must reach the
        # people whose answer is about to be cleared, not the freshly
        # pending roster (doc/attendances.md ordering rule).
        reset_notify_ids = reset ? going_member_ids(event.id) : []

        DB.transaction do
          DB[:date_polls].where(id: poll.id).update(
            selected_date_range_id: selected_date_range_id,
            closed_at: Time.now
          )

          DB[:events].where(id: event.id).update(
            start_date: date_range.start_date,
            end_date: date_range.end_date
          )

          # Mark "yes" voters on the winning range as going. An existing row
          # keeps its day set — overwriting with nil here would silently
          # widen a partial-day answer to whole-event — but re-normalized
          # against the event's window, which the update above just moved to
          # the winning range.
          yes_voter_ids = DB[:votes]
                          .where(date_range_id: selected_date_range_id, response: "yes")
                          .select_map(:user_id)

          reset_answers(event.id, yes_voter_ids) if reset

          updated_event = event.with(start_date: date_range.start_date, end_date: date_range.end_date)

          now = Time.now
          yes_voter_ids.each do |uid|
            mark_voter_going(updated_event, uid, now)
          end

          Broadcaster.object_changed("date_poll", poll.id)
          Broadcaster.object_changed("event", event.id)
        end

        APP_LOGGER.info { "[DatePolls::Close] Poll #{poll.id} closed on event #{event.id} with date range #{selected_date_range_id}" }
        DatePolls::OnClosed.call(
          event: event, date_range: date_range,
          yes_voter_ids: yes_voter_ids, reset_user_ids: reset_notify_ids
        )

        pool = PoolSerializer.new(membership: membership)
        pool.add(:event, [Event.find(event.id)])
        pool.add(:date_poll, [DatePoll.find(poll.id)])
        pool.add(:attendance, Attendance.for_event(event.id))
        Success({ objects: pool.to_a })
      end

      def going_member_ids(event_id)
        Attendance.for_event(event_id)
                  .select { |a| a.going? && !a.guest? }
                  .map { |a| a.user_id.to_s }
      end

      # Mirrors Events::Update#dates_changed?: only a real change clears the
      # answers; a poll that sets dates for the first time is not a change.
      def dates_changed?(event, date_range)
        if event.start_date.nil? || event.end_date.nil?
          false
        else
          [date_range.start_date, date_range.end_date] != [event.start_date, event.end_date]
        end
      end

      # Keep the people, clear the answers (doc/attendances.md): when the
      # winning range replaces existing dates, every row — member and guest
      # alike — reverts to pending, except yes-voters on the winner, whose
      # vote is their answer for the new window (mark_voter_going upserts
      # them right after, keeping their day set). Per-row broadcasts; the
      # pool never rewrites children on parent updates.
      def reset_answers(event_id, except_user_ids)
        except = except_user_ids.map(&:to_s)
        ids = Attendance.for_event(event_id)
                        .reject { |a| a.user_id && except.include?(a.user_id.to_s) }
                        .map(&:id)
        if ids.any?
          DB[:attendances].where(id: ids).update(status: "pending", days: nil, updated_at: Time.now)
          ids.each { |aid| Broadcaster.object_changed("attendance", aid) }
        end
      end

      # Server-initiated going transition for a yes voter: upsert their
      # member attendance row, carrying an existing row's day set forward
      # (normalized against the new event window).
      def mark_voter_going(event, user_id, now)
        existing = DB[:attendances].where(event_id: event.id, user_id: user_id).first
        days = existing && existing[:days] && existing[:days].map { |d| Date.parse(d) }
        days = Attendances.normalize_days(event, days)

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
                status: "going",
                days: days && Sequel.pg_jsonb(days.map(&:iso8601)),
                created_by_user_id: nil,
                created_at: now,
                updated_at: now
              )
              .first
        Broadcaster.object_changed("attendance", row[:id])
      end
    end
  end
end
