# typed: true
# frozen_string_literal: true

module DatePolls
  # Service to close a date poll by selecting a winning date range.
  module Close
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          event_id: T.any(String, UUID),
          current_user_id: T.any(String, UUID),
          selected_date_range_id: T.nilable(String)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(event_id:, current_user_id:, selected_date_range_id:)
        Event.find_result(event_id)
             .bind { |event| EventPolicy.new(event: event, user_id: current_user_id.to_s).authorize!(:close_poll, value: event) }
             .bind { |event| DatePoll.find_by_event_result(event.id).fmap { |poll| [event, poll] } }
             .bind { |(event, poll)| validate_not_resolved(event, poll) }
             .bind { |(event, poll)| validate_date_range(event, poll, selected_date_range_id) }
             .bind { |(event, poll, dr_id)| close_poll(event, poll, dr_id) }
      end

      private

      sig { params(event: Event, poll: DatePoll).returns(Result[T::Array[T.untyped], ServiceError]) }
      def validate_not_resolved(event, poll)
        if poll.closed_at
          T.cast(Failure(ServiceError.validation("Poll is already resolved")), Result[T::Array[T.untyped], ServiceError])
        else
          T.cast(Success([event, poll]), Result[T::Array[T.untyped], ServiceError])
        end
      end

      sig do
        params(
          event: Event,
          poll: DatePoll,
          selected_date_range_id: T.nilable(String)
        ).returns(Result[T::Array[T.untyped], ServiceError])
      end
      def validate_date_range(event, poll, selected_date_range_id)
        if selected_date_range_id.nil? || selected_date_range_id.empty?
          return T.cast(
            Failure(ServiceError.validation("selected_date_range_id is required")),
            Result[T::Array[T.untyped], ServiceError]
          )
        end

        date_range = DateRange.find(selected_date_range_id)
        unless date_range && date_range.date_poll_id == poll.id
          return T.cast(
            Failure(ServiceError.validation("Date range does not belong to this poll")),
            Result[T::Array[T.untyped], ServiceError]
          )
        end

        T.cast(Success([event, poll, selected_date_range_id]), Result[T::Array[T.untyped], ServiceError])
      end

      sig do
        params(event: Event, poll: DatePoll, selected_date_range_id: String)
          .returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def close_poll(event, poll, selected_date_range_id)
        date_range = T.must(DateRange.find(selected_date_range_id))
        yes_voter_ids = T.let([], T::Array[String])

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

          now = Time.now
          yes_voter_ids.each do |uid|
            existing = DB[:rsvps].where(event_id: event.id, user_id: uid).first
            if existing
              DB[:rsvps].where(id: existing[:id]).update(attending: true, updated_at: now)
              Broadcaster.object_changed("rsvp", existing[:id], workspace_id: event.workspace_id)
            else
              rsvp_id = SecureRandom.uuid
              DB[:rsvps].insert(id: rsvp_id, event_id: event.id, user_id: uid, attending: true, created_at: now, updated_at: now)
              Broadcaster.object_changed("rsvp", rsvp_id, workspace_id: event.workspace_id)
            end
          end

          Broadcaster.object_changed("date_poll", poll.id, workspace_id: event.workspace_id)
          Broadcaster.object_changed("event", event.id, workspace_id: event.workspace_id)
        end

        APP_LOGGER.info { "[DatePolls::Close] Poll #{poll.id} closed on event #{event.id} with date range #{selected_date_range_id}" }
        send_poll_closed_emails(event, poll, date_range, yes_voter_ids)

        pool = PoolSerializer.new(workspace_id: event.workspace_id)
        pool.add_event(T.must(Event.find(event.id)))
        pool.add_date_poll(T.must(DatePoll.find(poll.id)))
        Rsvp.for_event(event.id).each { |r| pool.add_rsvp(r) }
        T.cast(Success({ objects: pool.to_a }), Result[T::Hash[Symbol, T.untyped], ServiceError])
      end

      sig do
        params(event: Event, poll: DatePoll, date_range: DateRange, yes_voter_ids: T::Array[String]).void
      end
      def send_poll_closed_emails(event, poll, date_range, yes_voter_ids)
        all_date_range_ids = DateRange.ids_for_date_poll(poll.id)
        all_votes = Vote.for_date_range_ids(all_date_range_ids)
        voter_user_ids = all_votes.map { |v| v.user_id.to_s }.uniq
        users = User.for_ids(voter_user_ids)

        ics_content = IcsGenerator.generate(
          uid: event.id.to_s,
          summary: event.name,
          start_date: date_range.start_date,
          end_date: date_range.end_date,
          description: event.description,
          location: event.location_name,
          created_at: event.created_at
        )

        date_label = format_date_label(date_range.start_date, date_range.end_date)
        event_url = "#{ENV.fetch("FRONTEND_URL", "https://tayaway.com")}/events/#{event.id}"
        ics_filename = "#{event.name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")}.ics"

        users.each do |user|
          auto_rsvped = yes_voter_ids.include?(user.id.to_s)
          Mailers::PollClosed.send_email(
            email: user.email,
            user_name: user.name,
            event_name: event.name,
            date_label: date_label,
            event_url: event_url,
            ics_content: ics_content,
            ics_filename: ics_filename,
            auto_rsvped: auto_rsvped
          )
        end
      rescue StandardError => e
        APP_LOGGER.error { "[DatePolls::Close] Failed to send poll closed emails: #{e.class} - #{e.message}" }
      end

      sig { params(start_date: Date, end_date: Date).returns(String) }
      def format_date_label(start_date, end_date)
        if start_date == end_date
          start_date.strftime("%B %-d, %Y")
        elsif start_date.year == end_date.year && start_date.month == end_date.month
          "#{start_date.strftime("%B %-d")}-#{end_date.strftime("%-d, %Y")}"
        elsif start_date.year == end_date.year
          "#{start_date.strftime("%B %-d")} - #{end_date.strftime("%B %-d, %Y")}"
        else
          "#{start_date.strftime("%B %-d, %Y")} - #{end_date.strftime("%B %-d, %Y")}"
        end
      end
    end
  end
end
