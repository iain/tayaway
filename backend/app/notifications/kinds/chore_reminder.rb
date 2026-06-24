# frozen_string_literal: true

module Notifications
  module Kinds
    # Reminds an assigned person that one of their chores is due now. Fires
    # at the chore's wall-clock time on the assignment's date, via a job
    # scheduled when the assignment is created. Push is the headline
    # channel — a phone buzz at "your turn to cook" — with the in-app bell
    # as the always-on fallback. No email: a chore due *now* is a poor fit
    # for a channel that may sit unread for hours.
    module ChoreReminder
      class << self
        def key = :chore_reminder
        def default_channels = %i[push in_app]
        def supported_channels = %i[push in_app]

        def in_app_payload(chore_name:, event_name:, event_url:, **)
          {
            title: "Chore reminder",
            body: "It's your turn: #{chore_name} (#{event_name})",
            href: event_url
          }
        end
      end
    end
  end
end
