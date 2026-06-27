# frozen_string_literal: true

module ChoreRosters
  # Schedules the reminder for one assignment: a single future-dated job
  # that fires SendReminder at the chore's wall-clock time on the
  # assignment's date. Called once per assignment at create / autofill
  # time, so a chore that never gets a time, or a date already past,
  # simply schedules nothing.
  #
  # Timezone: the app stores dates and times without a zone, so the
  # reminder is built in the server's local time — correct for a
  # single-region deployment. Introducing per-event timezones would mean
  # combining the moment here against that zone instead. Known edge: a time
  # inside the spring-forward DST gap (e.g. 02:30 where the clock jumps
  # 02:00→03:00) is normalized by Ruby to the adjacent valid instant.
  module ScheduleReminder
    JOB_CLASS = "ChoreRosters::SendReminder::Job"

    class << self
      def call(assignment:, chore: nil)
        chore ||= Chore.find(assignment.chore_id)
        return unless chore&.time

        remind_at = combine(assignment.date, chore.time)
        return if remind_at <= Time.now

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

      private

      def combine(date, time)
        Time.new(date.year, date.month, date.day, time.hour, time.min, 0)
      end
    end
  end
end
