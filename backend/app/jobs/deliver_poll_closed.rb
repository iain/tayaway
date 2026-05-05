# frozen_string_literal: true

module Jobs
  class DeliverPollClosed < Base
    def initialize(email:, user_name:, event_name:, date_label:, event_url:, ics_content:, ics_filename:, auto_rsvped:)
      @email = email
      @user_name = user_name
      @event_name = event_name
      @date_label = date_label
      @event_url = event_url
      @ics_content = ics_content
      @ics_filename = ics_filename
      @auto_rsvped = auto_rsvped
    end

    def call
      Mailers::PollClosed.deliver_now(
        email: @email,
        user_name: @user_name,
        event_name: @event_name,
        date_label: @date_label,
        event_url: @event_url,
        ics_content: @ics_content,
        ics_filename: @ics_filename,
        auto_rsvped: @auto_rsvped
      )
    end
  end
end
