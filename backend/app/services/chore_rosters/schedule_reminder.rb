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

        # Stamp the time this job is for. If the chore's time is later edited,
        # SendReminder sees the mismatch and this job no-ops while a freshly
        # scheduled one fires — no need to find and cancel the old job.
        Jobs::Queue.enqueue(
          job_class: JOB_CLASS,
          args: { chore_assignment_id: assignment.id.to_s, expected_time: chore.time.strftime("%H:%M") },
          scheduled_at: remind_at
        )
      end

      private

      def combine(date, time)
        Time.new(date.year, date.month, date.day, time.hour, time.min, 0)
      end
    end
  end
end
