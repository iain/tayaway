# frozen_string_literal: true

module DatePolls
  # Service to add a date range to a date poll.
  module AddDateRange
    class << self
      def call(event_id:, membership:, start_date:, end_date:, id: nil)
        Auditable.around(
          service: "DatePolls::AddDateRange",
          actor: membership,
          subject_type: "date_range",
          subject_id: id
        ) do
          Success()
            .bind { Event.find_result(event_id) }
            .bind { |event| DatePoll.find_by_event_result(event.id).fmap { |poll| [event, poll] } }
            .bind { |(event, poll)| DatePollPolicy.enforce(:create_date_range, poll, membership: membership, event: event).fmap { |_| [event, poll] } }
            .bind { |(event, poll)| DatePoll.validate_open(poll).fmap { |_| [event, poll] } }
            .bind { |(event, poll)| parse_dates(start_date, end_date, event, poll) }
            .bind { |(event, poll, date_input)| insert_date_range(event, poll, date_input, id, membership) }
        end
      end

      private

      def parse_dates(start_date, end_date, event, poll)
        DateRangeInput.parse_strings(start_date, end_date).fmap { |date_input| [event, poll, date_input] }
      end

      def insert_date_range(event, poll, date_input, id, membership)
        dr_id = id || SecureRandom.uuid
        now = Time.now

        DB.transaction do
          inserted = DB[:date_ranges]
                     .returning(:id)
                     .insert_conflict
                     .insert(
                       id: dr_id,
                       date_poll_id: poll.id,
                       start_date: date_input.start_date,
                       end_date: date_input.end_date,
                       created_at: now,
                       updated_at: now
                     )
                     .first

          if inserted
            # The poll's payload lists its options and carries the close
            # permission derived from them, so it has to move with the range or
            # other clients sit on a stale copy — one whose updatedAt loses the
            # pool's newer-wins merge. The touch is what bumps it (the BEFORE
            # UPDATE trigger stamps the value).
            DB[:date_polls].where(id: poll.id).update(updated_at: Sequel::CURRENT_TIMESTAMP)
            Broadcaster.object_changed("date_range", dr_id)
            Broadcaster.object_changed("date_poll", poll.id)
          end
        end

        pool = PoolSerializer.new(membership: membership)
        pool.add(:date_poll, [DatePoll.find(poll.id)])
        pool.add(:date_range, [DateRange.find(dr_id)])
        Success({ objects: pool.to_a })
      end
    end
  end
end
