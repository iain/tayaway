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
  #
  # The re-checks read as a Result chain: each link looks up the next piece
  # of state the reminder needs, and any link that comes up empty short-
  # circuits to a Failure. Nobody reads that Failure — the worker only
  # retries on a raised exception — so a job whose world has changed simply
  # stops partway and sends nothing.
  module SendReminder
    class << self
      # @param expected_time [String, nil] the "HH:MM" this job was scheduled
      #   for; nil for legacy jobs queued before this argument existed, which
      #   skip the staleness check and fire on the chore's current time.
      def call(chore_assignment_id:, expected_time: nil)
        Success()
          .bind { ChoreAssignment.find_result(chore_assignment_id) }
          .bind { |assignment| current_chore(assignment, expected_time) }
          .bind { |ctx| add_event(ctx) }
          .bind { |ctx| ensure_member(ctx) }
          .bind { |ctx| deliver(ctx) }
      end

      private

      # The chore must still exist, still be timed, and still hold the time
      # this job was scheduled for — an edit since then makes the job stale.
      def current_chore(assignment, expected_time)
        chore = Chore.find(assignment.chore_id)
        if chore.nil? || chore.time.nil?
          Failure(:no_time)
        elsif expected_time && chore.time.strftime("%H:%M") != expected_time
          Failure(:stale_time)
        else
          Success({ assignment: assignment, chore: chore })
        end
      end

      def add_event(ctx)
        ChoreRoster.find_result(ctx[:chore].chore_roster_id)
                   .bind { |roster| Event.find_result(roster.event_id) }
                   .fmap { |event| ctx.merge(event: event) }
      end

      # Don't nag someone who has since left the workspace — an assignment
      # row can outlive its assignee's membership (a pinned one survives
      # member removal), and a reminder to a non-member is just noise.
      def ensure_member(ctx)
        member = WorkspaceMembership.find_by_workspace_and_user(
          ctx[:event].workspace_id, ctx[:assignment].user_id
        )
        if member
          Success(ctx)
        else
          Failure(:not_a_member)
        end
      end

      def deliver(ctx)
        assignment, chore, event = ctx.values_at(:assignment, :chore, :event)
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
        Success()
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
