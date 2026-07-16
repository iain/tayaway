# frozen_string_literal: true

module ChoreRosters
  # The surgical counterpart to Autofill: hands each upcoming unpinned
  # assignment whose holder isn't attending that day to someone who is,
  # touching nothing else. Rows are updated in place — ids survive, so
  # pending reminders stay valid and other clients see a plain update.
  #
  # The same past-is-history fences as Autofill apply (days before today,
  # today's already-started timed chores), and pinned assignments are never
  # moved — a hand-placed person is a deliberate choice, stale or not.
  # Replacements are picked with Autofill's fairness scoring, so fixing a
  # few holes doesn't pile them all onto one person.
  module ReassignStale
    class << self
      def call(roster_id:, workspace_id:, membership:)
        Auditable.around(
          service: "ChoreRosters::ReassignStale",
          actor: membership,
          subject_type: "chore_roster",
          subject_id: roster_id
        ) do
          Success()
            .bind { ChoreRoster.find_result(roster_id) }
            .bind { |roster| ChoreRosterPolicy.enforce(:edit, roster, membership: membership) }
            .bind { |roster| find_event(roster) }
            .bind { |roster, event| reassign(roster, event, membership) }
        end
      end

      private

      def find_event(roster)
        event = Event.find(roster.event_id)
        if event && event.start_date && event.end_date
          Success([roster, event])
        else
          Failure(ServiceError.validation("Event must have dates set"))
        end
      end

      def reassign(roster, event, membership)
        today = Timezones.today(event.timezone)
        chores = Chore.for_roster(roster.id)
        started_today_chore_ids = ChoreTime.started_today(chores, event.timezone).map { |c| c.id.to_s }

        # Going attendances — members and guests alike, keyed by attendance
        # id (doc/attendances.md phase 8) — same availability source as
        # Autofill.
        attendances = Attendance.for_event(event.id).select(&:going?)
        availability = build_availability(event, attendances)
        attendance_by_id = attendances.to_h { |a| [a.id.to_s, a] }
        # Legacy rows without the attendance link resolve through their
        # mirrored user_id; gone once user_id retires.
        attendance_id_by_user = attendances.reject(&:guest?).to_h { |a| [a.user_id.to_s, a.id.to_s] }
        available_days = Hash.new(0)
        availability.each_value do |attendance_ids|
          attendance_ids.each { |aid| available_days[aid] += 1 }
        end

        all = ChoreAssignment.for_roster(roster.id)
        stale = all.select do |a|
          key = holder_key(a, attendance_id_by_user)
          !a.pinned &&
            a.date >= today &&
            !(a.date == today && started_today_chore_ids.include?(a.chore_id.to_s)) &&
            !(key && (availability[a.date] || Set.new).include?(key))
        end.sort_by(&:date)

        # Load and occupancy from the full roster, minus the stale rows being
        # replaced — their holders are leaving those slots, so they must not
        # block or skew the picks.
        stale_ids = stale.map { |a| a.id.to_s }.to_set
        kept = all.reject { |a| stale_ids.include?(a.id.to_s) }
        load_count = Hash.new(0)
        chore_load = Hash.new(0)
        day_assignments = Hash.new { |h, k| h[k] = Set.new }
        chore_day_assignments = Hash.new { |h, k| h[k] = Set.new }
        kept.each do |a|
          key = holder_key(a, attendance_id_by_user)
          next unless key

          load_count[key] += 1
          chore_load[[key, a.chore_id.to_s]] += 1
          day_assignments[a.date] << key
          chore_day_assignments[[a.chore_id.to_s, a.date]] << key
        end

        reassigned = []
        DB.transaction do
          stale.each do |assignment|
            chosen = pick_replacement(
              assignment, availability, available_days,
              load_count, chore_load, day_assignments, chore_day_assignments
            )
            next unless chosen

            DB[:chore_assignments].where(id: assignment.id).update(
              # Mirrored member column for old clients; nil on guest rows.
              user_id: attendance_by_id.fetch(chosen).user_id&.to_s,
              attendance_id: chosen
            )
            Broadcaster.object_changed("chore_assignment", assignment.id)
            reassigned << assignment.id

            load_count[chosen] += 1
            chore_load[[chosen, assignment.chore_id.to_s]] += 1
            day_assignments[assignment.date] << chosen
            chore_day_assignments[[assignment.chore_id.to_s, assignment.date]] << chosen
          end
        end

        pool = PoolSerializer.new(membership: membership)
        if reassigned.any?
          updated = reassigned.map { |aid| ChoreAssignment.find(aid) }
          pool.add(:chore_assignment, updated)
        end
        Success({ objects: pool.to_a })
      end

      def pick_replacement(assignment, availability, available_days, load_count, chore_load, day_assignments, chore_day_assignments)
        available = availability[assignment.date] || Set.new
        chore_id = assignment.chore_id.to_s

        eligible = available.reject do |aid|
          chore_day_assignments[[chore_id, assignment.date]].include?(aid) ||
            day_assignments[assignment.date].include?(aid)
        end
        if eligible.empty?
          eligible = available.reject do |aid|
            chore_day_assignments[[chore_id, assignment.date]].include?(aid)
          end
        end

        eligible.min_by do |aid|
          attendee_available = available_days[aid].zero? ? 1 : available_days[aid]
          [
            load_count[aid].to_f / attendee_available,
            chore_load[[aid, chore_id]],
            attendee_available
          ]
        end
      end

      def build_availability(event, attendances)
        availability = Hash.new { |h, k| h[k] = Set.new }
        attendances.each do |attendance|
          attendance.effective_days(event).each do |date|
            availability[date] << attendance.id.to_s
          end
        end
        availability
      end

      # The attendance id behind an assignment's holder; legacy rows without
      # the link resolve through their mirrored user_id.
      def holder_key(assignment, attendance_id_by_user)
        assignment.attendance_id&.to_s || attendance_id_by_user[assignment.user_id&.to_s]
      end
    end
  end
end
