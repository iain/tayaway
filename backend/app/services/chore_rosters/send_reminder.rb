# frozen_string_literal: true

module ChoreRosters
  # Delivers the "it's your turn" reminder for a single chore assignment.
  # Runs from a job scheduled at the chore's time (see ScheduleReminder),
  # so it re-reads current state and quietly no-ops if the world moved on:
  # the assignment was deleted, the chore was removed, its time cleared or
  # edited (the job's `expected_time` no longer matches), or the assignee
  # has since left the workspace. Time edits cancel the pending job up front;
  # this re-check keeps harmless any job that slipped through (in flight, or
  # left behind by a re-autofill).
  module SendReminder
    class << self
      # @param expected_time [String, nil] the "HH:MM" this job was scheduled
      #   for; nil for legacy jobs queued before this argument existed, which
      #   skip the staleness check and fire on the chore's current time.
      def call(chore_assignment_id:, expected_time: nil)
        assignment = ChoreAssignment.find(chore_assignment_id)
        return unless assignment

        chore = Chore.find(assignment.chore_id)
        return unless chore&.time
        return if expected_time && chore.time.strftime("%H:%M") != expected_time

        roster = ChoreRoster.find(chore.chore_roster_id)
        return unless roster

        event = Event.find(roster.event_id)
        return unless event

        # Don't nag someone who has since left the workspace — an assignment
        # row can outlive its assignee's membership (a pinned one survives
        # member removal), and a reminder to a non-member is just noise.
        return unless WorkspaceMembership.find_by_workspace_and_user(event.workspace_id, assignment.user_id)

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
    # the worker invokes `run(chore_assignment_id:, expected_time:)`.
    class Job < Jobs::Base
      def call(chore_assignment_id:, expected_time: nil)
        SendReminder.call(chore_assignment_id: chore_assignment_id, expected_time: expected_time)
      end
    end
  end
end
