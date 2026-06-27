# frozen_string_literal: true

module ChoreRosters
  # Autofill algorithm: deletes non-pinned assignments, then redistributes fairly.
  # Respects RSVP availability, pinned assignments, and a one-chore-per-day soft rule.
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

        # Build availability map from attending RSVPs
        rsvps = Rsvp.for_event(event.id).select(&:attending)
        availability = build_availability(dates, rsvps, event_start, event_end)

        chores = Chore.for_roster(roster.id)

        # Guard against pathological cases (e.g. 60-day event with 20 chores = 1200 rows)
        max_slots = dates.length * chores.sum(&:people_per_day)
        if max_slots > 1000
          return Failure(ServiceError.validation("Too many assignments to autofill (#{max_slots} slots). Reduce the number of chores or shorten the event dates."))
        end

        deleted = []
        pool = PoolSerializer.new(membership: membership)

        DB.transaction do
          # Delete all non-pinned assignments and track them
          non_pinned_ids = DB[:chore_assignments]
                           .join(:chores, id: :chore_id)
                           .where(Sequel[:chores][:chore_roster_id] => roster.id)
                           .where(Sequel[:chore_assignments][:pinned] => false)
                           .select_map(Sequel[:chore_assignments][:id])

          if non_pinned_ids.any?
            DeletedItems.bulk_insert(workspace_id, "chore_assignment", non_pinned_ids)
            deleted = non_pinned_ids.map { |aid| { objectType: "choreAssignment", id: aid.to_s } }
            DB[:chore_assignments].where(id: non_pinned_ids).delete
          end

          # Compute load from pinned assignments
          pinned = ChoreAssignment.for_roster(roster.id)
          load_count = Hash.new(0)
          chore_load = Hash.new(0) # key: [user_id, chore_id] => count
          pinned.each do |a|
            load_count[a.user_id.to_s] += 1
            chore_load[[a.user_id.to_s, a.chore_id.to_s]] += 1
          end

          # Compute available_days per user
          available_days = {}
          availability.each do |_date, user_ids|
            user_ids.each { |uid| available_days[uid] = (available_days[uid] || 0) + 1 }
          end

          # Build per-day assignment tracker: day -> Set<user_id> of already assigned
          day_assignments = Hash.new { |h, k| h[k] = Set.new }
          # Build per-chore-day tracker: [chore_id, date] -> Set<user_id>
          chore_day_assignments = Hash.new { |h, k| h[k] = Set.new }

          pinned.each do |a|
            day_assignments[a.date] << a.user_id.to_s
            chore_day_assignments[[a.chore_id.to_s, a.date]] << a.user_id.to_s
          end

          # For each day (chronological), for each chore, fill empty slots
          now = Time.now
          new_rows = []
          dates.each_with_index do |date, day_index|
            available_today = availability[date] || Set.new

            rotated_chores = chores.rotate(day_index)
            rotated_chores.each do |chore|
              existing_count = chore_day_assignments[[chore.id.to_s, date]].size
              slots_needed = chore.people_per_day - existing_count

              slots_needed.times do
                # Find eligible: available today, not on this chore-day already
                eligible = available_today.select do |uid|
                  !chore_day_assignments[[chore.id.to_s, date]].include?(uid) &&
                    !day_assignments[date].include?(uid)
                end

                # Relax one-per-day rule if no candidates found
                if eligible.empty?
                  eligible = available_today.select do |uid|
                    !chore_day_assignments[[chore.id.to_s, date]].include?(uid)
                  end
                end

                break if eligible.empty?

                # Pick person with fewest assignments on THIS chore (variety), then
                # lowest overall load/available_days ratio (fairness), then fewest available days
                chosen = eligible.min_by do |uid|
                  user_available = available_days[uid] || 1
                  [
                    chore_load[[uid, chore.id.to_s]],
                    load_count[uid].to_f / user_available,
                    user_available
                  ]
                end

                next unless chosen

                new_rows << {
                  id: SecureRandom.uuid,
                  chore_id: chore.id,
                  user_id: chosen,
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

        schedule_reminders(roster, chores)

        # Serialize full roster state
        roster = ChoreRoster.find(roster.id)
        pool.add(:chore_roster, [roster])

        Success({ objects: pool.to_a, deleted: deleted })
      end

      # Post-commit: every freshly autofilled (unpinned) assignment gets a
      # reminder if its chore is timed and the moment is still ahead.
      # Pinned assignments kept their reminder from when they were created.
      # Isolated like other notification work so a scheduling hiccup can't
      # roll back the autofill the user just ran.
      #
      # Re-running autofill recreates unpinned assignments with new ids, so
      # the previous run's jobs reference now-deleted assignments. Those are
      # left to fire and no-op (SendReminder finds nothing) rather than being
      # hunted down — they sit outside the worker's runnable range until
      # their scheduled time, so they don't burden the hot path.
      def schedule_reminders(roster, chores)
        chores_by_id = chores.to_h { |c| [c.id.to_s, c] }
        Notifications::Safely.deliver(context: "ChoreRosters::Autofill#reminders") do
          ChoreAssignment.for_roster(roster.id).reject(&:pinned).each do |assignment|
            ScheduleReminder.call(assignment: assignment, chore: chores_by_id[assignment.chore_id.to_s])
          end
        end
      end

      def build_availability(dates, rsvps, event_start, event_end)
        availability = {}
        dates.each { |d| availability[d] = Set.new }

        rsvps.each do |rsvp|
          rsvp_start = rsvp.start_date || event_start
          rsvp_end = rsvp.end_date || event_end

          dates.each do |d|
            availability[d] << rsvp.user_id.to_s if d >= rsvp_start && d <= rsvp_end
          end
        end

        availability
      end
    end
  end
end
