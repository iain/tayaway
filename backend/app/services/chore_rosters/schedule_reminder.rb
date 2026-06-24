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
  # combining the moment here against that zone instead.
  module ScheduleReminder
    JOB_CLASS = "ChoreRosters::SendReminder::Job"

    class << self
      def call(assignment:, chore: nil)
        chore ||= Chore.find(assignment.chore_id)
        return unless chore&.time

        remind_at = combine(assignment.date, chore.time)
        return if remind_at <= Time.now

        Jobs::Queue.enqueue(
          job_class: JOB_CLASS,
          args: { chore_assignment_id: assignment.id.to_s },
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
