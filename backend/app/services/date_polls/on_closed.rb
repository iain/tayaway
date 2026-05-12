# frozen_string_literal: true

module DatePolls
  # Fans a poll_closed notification out to every voter across every range
  # of the poll — not just yes-voters on the winning range — so the no-
  # voters also learn the dates are locked. The kind's copy branches on
  # `auto_rsvped` so yes-voters on the winning range get the "you're in"
  # message and everyone else gets the RSVP prompt.
  module OnClosed
    class << self
      def call(event:, date_range:, yes_voter_ids:)
        Notifications::Safely.deliver(context: "DatePolls::OnClosed") do
          all_date_range_ids = DateRange.ids_for_date_poll(date_range.date_poll_id)
          all_votes = Vote.for_date_range_ids(all_date_range_ids)
          voter_user_ids = all_votes.map { |v| v.user_id.to_s }.uniq
          return if voter_user_ids.empty?

          users = User.for_ids(voter_user_ids)
          ics_content = build_ics(event, date_range)
          date_label = format_date_label(date_range.start_date, date_range.end_date)
          event_url = "#{APP_CONFIG.frontend_url}/events/#{event.id}"
          ics_filename = "#{event.name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")}.ics"

          users.each do |user|
            Notifications::Dispatch.call(
              kind: :poll_closed,
              user_id: user.id.to_s,
              workspace_id: event.workspace_id.to_s,
              data: {
                email: user.email.to_s,
                user_name: user.name,
                event_name: event.name,
                date_label: date_label,
                event_url: event_url,
                ics_content: ics_content,
                ics_filename: ics_filename,
                auto_rsvped: yes_voter_ids.include?(user.id.to_s)
              }
            )
          end
        end
      end

      private

      def build_ics(event, date_range)
        IcsGenerator.generate(
          uid: event.id.to_s,
          summary: event.name,
          start_date: date_range.start_date,
          end_date: date_range.end_date,
          description: event.description,
          location: event.location_name,
          created_at: event.created_at
        )
      end

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
