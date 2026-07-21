# frozen_string_literal: true

module ChoreRosters
  # Autofill algorithm: deletes non-pinned assignments from today onward, then
  # redistributes the remaining days fairly. Respects RSVP availability, pinned
  # assignments, and a one-chore-per-day soft rule.
  #
  # Days already past (in the event's zone) are a record of who actually did
  # what and are never rewritten — mid-event attendance changes are absorbed by
  # re-running autofill, which rebalances only today onward while still
  # counting past work in each person's load. The same holds within today:
  # a timed chore whose moment has already arrived keeps its rows and slots
  # (see ChoreTime.started_today) — only what still lies ahead is refilled.
  module Autofill
    class << self
      def call(roster_id:, workspace_id:, membership:)
        Auditable.around(
          service: "ChoreRosters::Autofill",
          actor: membership,
          subject_type: "chore_roster",
          subject_id: roster_id
        ) do
          Success()
            .bind { ChoreRoster.find_result(roster_id) }
            .bind { |roster| ChoreRosterPolicy.enforce(:edit, roster, membership: membership) }
            .bind { |roster| find_event(roster) }
            .bind { |roster, event| run_autofill(roster, event, workspace_id, membership) }
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

      def run_autofill(roster, event, workspace_id, membership)
        event_start = event.start_date
        event_end = event.end_date
        dates = (event_start..event_end).to_a
        today = Timezones.today(event.timezone)
        fill_dates = dates.select { |date| date >= today }

        if fill_dates.empty?
          return Failure(ServiceError.validation("The event is over, so there are no days left to fill"))
        end

        # Build availability from going attendances — members and guests
        # alike, keyed by attendance id (doc/attendances.md phase 8). Past
        # days stay in the map: they feed available_days below, so someone
        # who already left still gets their whole stay counted when balancing
        # what remains.
        attendances = Attendance.for_event(event.id).select(&:going?)
        availability = build_availability(dates, attendances, event)
        attendance_by_id = attendances.to_h { |a| [a.id.to_s, a] }
        # Legacy rows without the attendance link resolve through their
        # mirrored user_id; gone once user_id retires.
        attendance_id_by_user = attendances.reject(&:guest?).to_h { |a| [a.user_id.to_s, a.id.to_s] }

        chores = Chore.for_roster(roster.id)
        started_today_chore_ids = ChoreTime.started_today(chores, event.timezone).map(&:id)

        # Guard against pathological cases (e.g. 60-day event with 20 chores = 1200 rows)
        max_slots = fill_dates.length * chores.sum(&:people_per_day)
        if max_slots > 1000
          return Failure(ServiceError.validation("Too many assignments to autofill (#{max_slots} slots). Reduce the number of chores or shorten the event dates."))
        end

        deleted = []
        pool = PoolSerializer.new(membership: membership)

        DB.transaction do
          # Delete non-pinned assignments from today onward and track them.
          # Earlier days are history and keep their rows, as does today's
          # occurrence of any chore that has already started.
          non_pinned_ids = DB[:chore_assignments]
                           .join(:chores, id: :chore_id)
                           .where(Sequel[:chores][:chore_roster_id] => roster.id)
                           .where(Sequel[:chore_assignments][:pinned] => false)
                           .where { Sequel[:chore_assignments][:date] >= today }
                           .exclude(
                             Sequel[:chore_assignments][:date] => today,
                             Sequel[:chore_assignments][:chore_id] => started_today_chore_ids
                           )
                           .select_map(Sequel[:chore_assignments][:id])

          if non_pinned_ids.any?
            DeletedItems.bulk_insert(workspace_id, "chore_assignment", non_pinned_ids)
            deleted = non_pinned_ids.map { |aid| { objectType: "choreAssignment", id: aid.to_s } }
            DB[:chore_assignments].where(id: non_pinned_ids).delete

            # Broadcast one deletion signal per assignment so connected clients
            # drop the rows (mirrors ClearUnpinned) — the roster broadcast below
            # only adds and updates, it can't remove anything from their pools.
            non_pinned_ids.each do |aid|
              Broadcaster.object_deleted("chore_assignment", aid, topics: [Topic.workspace(workspace_id)])
            end
          end

          # Compute load from what survived the delete: pinned assignments plus
          # the past-day record. Counting past work here is what keeps the
          # remaining days fair — someone who already did two mornings isn't
          # handed the same share of what's left as someone who just arrived.
          kept = ChoreAssignment.for_roster(roster.id)
          load_count = Hash.new(0)
          chore_load = Hash.new(0) # key: [attendance_id, chore_id] => count

          # Build per-day assignment tracker: day -> Set<attendance_id> of already assigned
          day_assignments = Hash.new { |h, k| h[k] = Set.new }
          # Build per-chore-day tracker: [chore_id, date] -> Set<attendance_id>
          chore_day_assignments = Hash.new { |h, k| h[k] = Set.new }

          kept.each do |a|
            key = holder_key(a, attendance_id_by_user)
            next unless key

            load_count[key] += 1
            chore_load[[key, a.chore_id.to_s]] += 1
            day_assignments[a.date] << key
            chore_day_assignments[[a.chore_id.to_s, a.date]] << key
          end

          # Compute available_days per attendance
          available_days = {}
          availability.each do |_date, attendance_ids|
            attendance_ids.each { |aid| available_days[aid] = (available_days[aid] || 0) + 1 }
          end

          # For each remaining day (chronological), for each chore, fill empty slots
          now = Time.now
          new_rows = []
          fill_dates.each_with_index do |date, day_index|
            available_today = availability[date] || Set.new

            rotated_chores = chores.rotate(day_index)
            rotated_chores.each do |chore|
              next if date == today && started_today_chore_ids.include?(chore.id)

              existing_count = chore_day_assignments[[chore.id.to_s, date]].size
              slots_needed = chore.people_per_day - existing_count

              slots_needed.times do
                # Find eligible: available today, not on this chore-day already
                eligible = available_today.select do |aid|
                  !chore_day_assignments[[chore.id.to_s, date]].include?(aid) &&
                    !day_assignments[date].include?(aid)
                end

                # Relax one-per-day rule if no candidates found
                if eligible.empty?
                  eligible = available_today.select do |aid|
                    !chore_day_assignments[[chore.id.to_s, date]].include?(aid)
                  end
                end

                break if eligible.empty?

                # Pick person with the lowest overall load/available_days ratio
                # (fairness), breaking ties toward the person who has done THIS
                # chore least (variety), then fewest available days. Fairness
                # leads so someone already pinned to their fair share isn't
                # handed extra work just because they haven't rotated through a
                # given chore yet — pinned assignments already count in load_count.
                chosen = eligible.min_by do |aid|
                  attendee_available = available_days[aid] || 1
                  [
                    load_count[aid].to_f / attendee_available,
                    chore_load[[aid, chore.id.to_s]],
                    attendee_available
                  ]
                end

                next unless chosen

                new_rows << {
                  id: SecureRandom.uuid,
                  chore_id: chore.id,
                  # Mirrored member column for old clients; nil on guest rows.
                  user_id: attendance_by_id.fetch(chosen).user_id&.to_s,
                  attendance_id: chosen,
                  date: date,
                  pinned: false,
                  note: nil,
                  created_at: now,
                  updated_at: now
                }

                # Update trackers
                load_count[chosen] += 1
                chore_load[[chosen, chore.id.to_s]] += 1
                day_assignments[date] << chosen
                chore_day_assignments[[chore.id.to_s, date]] << chosen
              end
            end
          end

          DB[:chore_assignments].multi_insert(new_rows) if new_rows.any?

          # Single broadcast for the entire roster change
          Broadcaster.object_changed("chore_roster", roster.id)
        end

        schedule_reminders(roster, chores, today)

        # Serialize full roster state
        roster = ChoreRoster.find(roster.id)
        pool.add(:chore_roster, [roster])

        Success({ objects: pool.to_a, deleted: deleted })
      end

      # Post-commit: every freshly autofilled (unpinned, today-onward)
      # assignment gets a reminder if its chore is timed and the moment is
      # still ahead. Pinned assignments kept their reminder from when they
      # were created; unpinned rows on past days survived the refill as
      # history and need none.
      # Isolated like other notification work so a scheduling hiccup can't
      # roll back the autofill the user just ran.
      #
      # Re-running autofill recreates unpinned assignments with new ids, so
      # the previous run's jobs reference now-deleted assignments. Those are
      # left to fire and no-op (SendReminder finds nothing) rather than being
      # hunted down — they sit outside the worker's runnable range until
      # their scheduled time, so they don't burden the hot path.
      def schedule_reminders(roster, chores, today)
        chores_by_id = chores.to_h { |c| [c.id.to_s, c] }
        Notifications::Safely.deliver(context: "ChoreRosters::Autofill#reminders") do
          timezone = ScheduleReminder.timezone_for_roster(roster.id)
          fresh = ChoreAssignment.for_roster(roster.id).reject(&:pinned).select { |a| a.date >= today }
          fresh.each do |assignment|
            ScheduleReminder.call(
              assignment: assignment, chore: chores_by_id[assignment.chore_id.to_s], timezone: timezone
            )
          end
        end
      end

      def build_availability(dates, attendances, event)
        availability = {}
        dates.each { |d| availability[d] = Set.new }

        attendances.each do |attendance|
          attended = attendance.effective_days(event).to_set
          dates.each do |d|
            availability[d] << attendance.id.to_s if attended.include?(d)
          end
        end

        availability
      end

      # The attendance id behind an assignment's holder; legacy rows without
      # the link resolve through their mirrored user_id, unresolvable rows
      # drop out of the trackers.
      def holder_key(assignment, attendance_id_by_user)
        assignment.attendance_id&.to_s || attendance_id_by_user[assignment.user_id&.to_s]
      end
    end
  end
end
