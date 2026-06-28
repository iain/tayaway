# frozen_string_literal: true

module ChoreRosters
  # Schedules the reminder for one assignment: a single future-dated job
  # that fires SendReminder at the chore's wall-clock time on the
  # assignment's date. Called once per assignment at create / autofill
  # time, so a chore that never gets a time, or a date already past,
  # simply schedules nothing.
  #
  # Timezone: the moment is the chore's wall-clock time on the assignment's
  # date, read in the event's zone (see Timezones.resolve), so it fires at the
  # right local time even across a DST change mid-event. Callers pass the zone
  # in — they already hold the roster/event — via timezone_for_roster.
  module ScheduleReminder
    JOB_CLASS = "ChoreRosters::SendReminder::Job"

    class << self
      def call(assignment:, timezone:, chore: nil)
        chore ||= Chore.find(assignment.chore_id)
        return unless chore&.time

        remind_at = Timezones.resolve(
          date: assignment.date, hour: chore.time.hour, min: chore.time.min, zone: timezone
        )
        if remind_at > Time.now
          # Stamp the time this job is for. Editing the time cancels the pending
          # job and reschedules (see UpdateChore#reschedule_reminders); this
          # stamp is the backstop for a job we couldn't cancel — one already in
          # flight, or left over from a re-autofill — which SendReminder no-ops
          # when the stamp no longer matches the chore's current time.
          Jobs::Queue.enqueue(
            job_class: JOB_CLASS,
            args: { chore_assignment_id: assignment.id.to_s, expected_time: chore.time.strftime("%H:%M") },
            scheduled_at: remind_at
          )
        end
      end

      # Drops any still-pending reminder for this assignment, so rescheduling
      # to a new time can't leave the old job behind. A job already in flight
      # (locked by a worker) is left alone — SendReminder's stamp/existence
      # checks keep it harmless. Editing the time back to an earlier value
      # would otherwise resurrect that earlier job, since its stamp matches
      # the chore's time once more and nothing else removes it.
      def cancel(assignment:)
        DB[Jobs::Queue::TABLE]
          .where(job_class: JOB_CLASS, locked_at: nil)
          .where(Sequel.lit("args ->> 'chore_assignment_id' = ?", assignment.id.to_s))
          .delete
      end

      # The IANA zone a roster's reminders fire in: its event's timezone.
      # Resolved once per scheduling pass and passed into .call.
      def timezone_for_roster(roster_id)
        Event.find(ChoreRoster.find(roster_id).event_id).timezone
      end

      # Re-queues every pending reminder for an event's chores in the event's
      # (just-changed) zone. Cancelling first stops the old instant lingering;
      # .call no-ops for an untimed chore or a moment now past.
      def reschedule_for_event(event)
        roster = ChoreRoster.find_by_event(event.id)
        return unless roster

        Chore.for_roster(roster.id).each do |chore|
          ChoreAssignment.for_chore(chore.id).each do |assignment|
            cancel(assignment: assignment)
            call(assignment: assignment, chore: chore, timezone: event.timezone)
          end
        end
      end
    end
  end
end
