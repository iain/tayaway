# frozen_string_literal: true

module Jobs
  class DeliverPollClosed < Base
    def call(email:, user_name:, event_name:, date_label:, event_url:, ics_content:, ics_filename:, auto_rsvped:)
      Mailers::PollClosed.perform_delivery(
        email: email,
        user_name: user_name,
        event_name: event_name,
        date_label: date_label,
        event_url: event_url,
        ics_content: ics_content,
        ics_filename: ics_filename,
        auto_rsvped: auto_rsvped
      )
    end
  end
end
