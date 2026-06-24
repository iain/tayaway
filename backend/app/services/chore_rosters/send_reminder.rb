# frozen_string_literal: true

module ChoreRosters
  # Delivers the "it's your turn" reminder for a single chore assignment.
  # Runs from a job scheduled at the chore's time (see ScheduleReminder),
  # so it re-reads current state and quietly no-ops if the world moved on:
  # the assignment was deleted, the chore was removed, or its time cleared.
  # That keeps a stale scheduled job harmless instead of needing the
  # scheduler to chase down and cancel jobs on every edit.
  module SendReminder
    class << self
      def call(chore_assignment_id:)
        assignment = ChoreAssignment.find(chore_assignment_id)
        return unless assignment

        chore = Chore.find(assignment.chore_id)
        return unless chore&.time

        roster = ChoreRoster.find(chore.chore_roster_id)
        return unless roster

        event = Event.find(roster.event_id)
        return unless event

        Notifications::Safely.deliver(context: "ChoreRosters::SendReminder") do
          Notifications::Dispatch.call(
            kind: :chore_reminder,
            user_id: assignment.user_id.to_s,
            workspace_id: event.workspace_id.to_s,
            data: {
              chore_name: chore.name,
              event_name: event.name,
              event_url: APP_CONFIG.frontend_url.path("/events/#{event.id}/chores")
            }
          )
        end
      end
    end

    # The persisted job. One per assignment, scheduled at the chore time;
    # the worker invokes `run(chore_assignment_id:)`.
    class Job < Jobs::Base
      def call(chore_assignment_id:)
        SendReminder.call(chore_assignment_id: chore_assignment_id)
      end
    end
  end
end
