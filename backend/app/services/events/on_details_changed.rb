# frozen_string_literal: true

module Events
  # Fans an event_details_changed notification out to going members
  # except the actor, but only when the change actually moves dates or
  # location. Renames and description tweaks aren't surfaced — they're
  # too noisy in active planning.
  #
  # `recipient_user_ids` lets the caller pin the audience: a date change
  # resets every row to pending, so Events::Update resolves the
  # people-who-had-answered *before* the revert and passes them in.
  module OnDetailsChanged
    class << self
      def call(before:, after:, actor_user_id:, recipient_user_ids: nil)
        Notifications::Safely.deliver(context: "Events::OnDetailsChanged") do
          change_summary = summarize_changes(before, after)
          return unless change_summary

          going = recipient_user_ids ||
                  Attendance.for_event(after.id).select { |a| a.going? && !a.guest? }.map { |a| a.user_id.to_s }
          recipient_ids = going - [actor_user_id.to_s]
          return if recipient_ids.empty?

          event_url = APP_CONFIG.frontend_url.path("/events/#{after.id}")
          users = User.for_ids(recipient_ids)

          users.each do |user|
            Notifications::Dispatch.call(
              kind: :event_details_changed,
              user_id: user.id.to_s,
              workspace_id: after.workspace_id.to_s,
              data: {
                email: user.email.to_s,
                recipient_name: user.name,
                event_name: after.name,
                change_summary: change_summary,
                event_url: event_url
              }
            )
          end
        end
      end

      private

      def summarize_changes(before, after)
        parts = []
        parts << "new dates" if before.start_date != after.start_date || before.end_date != after.end_date
        parts << "new location" if before.location_name != after.location_name
        return nil if parts.empty?

        case parts.length
        when 1 then parts.first.capitalize
        else parts.join(" and ").capitalize
        end
      end
    end
  end
end
