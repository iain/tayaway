# typed: true
# frozen_string_literal: true

module ChoreRosters
  # Autofill algorithm: deletes non-pinned assignments, then redistributes fairly.
  # Respects RSVP availability, pinned assignments, and a one-chore-per-day soft rule.
  module Autofill
    class << self
      extend T::Sig
      include Result::Methods

      sig do
        params(
          roster_id: T.any(String, UUID),
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def call(roster_id:, workspace_id:)
        ChoreRoster.find_result(roster_id)
                   .bind { |roster| find_event(roster) }
                   .bind { |roster, event| run_autofill(roster, event, workspace_id) }
      end

      private

      sig { params(roster: ChoreRoster).returns(Result[T::Array[T.untyped], ServiceError]) }
      def find_event(roster)
        event = Event.find(roster.event_id)
        if event && event.start_date && event.end_date
          T.cast(Success([roster, event]), Result[T::Array[T.untyped], ServiceError])
        else
          T.cast(
            Failure(ServiceError.validation("Event must have dates set")),
            Result[T::Array[T.untyped], ServiceError]
          )
        end
      end

      sig do
        params(
          roster: ChoreRoster,
          event: Event,
          workspace_id: T.any(String, UUID)
        ).returns(Result[T::Hash[Symbol, T.untyped], ServiceError])
      end
      def run_autofill(roster, event, workspace_id)
        event_start = T.must(event.start_date)
        event_end = T.must(event.end_date)
        dates = (event_start..event_end).to_a

        # Build availability map from attending RSVPs
        rsvps = Rsvp.for_event(event.id).select(&:attending)
        availability = build_availability(dates, rsvps, event_start, event_end)

        chores = Chore.for_roster(roster.id)
        deleted = []
        pool = PoolSerializer.new(workspace_id: workspace_id)

        DB.transaction do
          # Delete all non-pinned assignments and track them
          non_pinned_ids = DB[:chore_assignments]
                           .join(:chores, id: :chore_id)
                           .where(Sequel[:chores][:chore_roster_id] => roster.id)
                           .where(Sequel[:chore_assignments][:pinned] => false)
                           .select_map(Sequel[:chore_assignments][:id])

          non_pinned_ids.each do |aid|
            DB[:deleted_items].insert(workspace_id: workspace_id, object_type: "chore_assignment", object_id: aid)
            Broadcaster.object_deleted("chore_assignment", aid, workspace_id: workspace_id)
            deleted << { objectType: "choreAssignment", id: aid.to_s }
          end

          DB[:chore_assignments]
            .where(id: non_pinned_ids)
            .delete if non_pinned_ids.any?

          # Compute load from pinned assignments
          pinned = ChoreAssignment.for_roster(roster.id)
          load_count = Hash.new(0)
          pinned.each { |a| load_count[a.user_id.to_s] += 1 }

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
          dates.each do |date|
            available_today = availability[date] || Set.new

            chores.each do |chore|
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

                # Pick person with lowest load/available_days ratio (proportional fairness)
                # Tie-break: prefer person with fewer available days (they need to be scheduled sooner)
                chosen = eligible.min_by do |uid|
                  user_available = available_days[uid] || 1
                  [load_count[uid].to_f / user_available, user_available]
                end

                next unless chosen

                assignment_id = SecureRandom.uuid
                DB[:chore_assignments].insert(
                  id: assignment_id,
                  chore_id: chore.id,
                  user_id: chosen,
                  date: date,
                  pinned: false,
                  note: nil,
                  created_at: now,
                  updated_at: now
                )
                Broadcaster.object_changed("chore_assignment", assignment_id, workspace_id: workspace_id)

                # Update trackers
                load_count[chosen] += 1
                day_assignments[date] << chosen
                chore_day_assignments[[chore.id.to_s, date]] << chosen
              end

              Broadcaster.object_changed("chore", chore.id, workspace_id: workspace_id)
            end
          end

          Broadcaster.object_changed("chore_roster", roster.id, workspace_id: workspace_id)
        end

        # Serialize full roster state
        roster = T.must(ChoreRoster.find(roster.id))
        pool.add_chore_roster(roster)

        T.cast(
          Success({ objects: pool.to_a, deleted: deleted }),
          Result[T::Hash[Symbol, T.untyped], ServiceError]
        )
      end

      sig do
        params(
          dates: T::Array[Date],
          rsvps: T::Array[Rsvp],
          event_start: Date,
          event_end: Date
        ).returns(T::Hash[Date, Set])
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
