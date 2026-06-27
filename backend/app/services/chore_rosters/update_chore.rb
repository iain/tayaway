# frozen_string_literal: true

module ChoreRosters
  # Service to update a chore (name, people_per_day, position, time).
  #
  # `time` is tri-state: the `:unset` default means "leave the time alone",
  # while an explicit value (including blank, which clears it) edits it.
  module UpdateChore
    class << self
      def call(chore_id:, workspace_id:, membership:, name: nil, people_per_day: nil, position: nil, time: :unset)
        Auditable.around(
          service: "ChoreRosters::UpdateChore",
          actor: membership,
          subject_type: "chore",
          subject_id: chore_id,
          context: { name: name }
        ) do
          Success()
            .bind { Chore.find_result(chore_id) }
            .bind { |chore| ChorePolicy.enforce(:edit, chore, membership: membership) }
            .bind { |chore| validate_and_update(chore, workspace_id, name, people_per_day, position, time, membership) }
        end
      end

      private

      def validate_and_update(chore, workspace_id, name, people_per_day, position, time, membership)
        updates = {}

        if name
          if name.empty?
            return Failure(ServiceError.validation("Name cannot be empty"))
          end
          if name.length > ValidationLimits::SHORT_STRING
            return Failure(ServiceError.validation("Name is too long (maximum #{ValidationLimits::SHORT_STRING} characters)"))
          end
          updates[:name] = name
        end

        if people_per_day
          if people_per_day < 1 || people_per_day > ValidationLimits::PEOPLE_PER_DAY_MAX
            return Failure(ServiceError.validation("People per day must be between 1 and #{ValidationLimits::PEOPLE_PER_DAY_MAX}"))
          end
          updates[:people_per_day] = people_per_day
        end

        updates[:position] = position if position

        # Only touch `time` when an explicit value was supplied, and only mark
        # it changed when the stored value actually differs — rescheduling on
        # an unchanged time would queue a second job that fires alongside the
        # first.
        time_changed = false
        unless time == :unset
          normalized = ChoreTime.normalize(time)
          return normalized if normalized.failure?

          new_time = normalized.value!
          if new_time != chore.time&.strftime("%H:%M")
            updates[:time] = new_time
            time_changed = true
          end
        end

        if updates.empty?
          return Failure(ServiceError.validation("No changes provided"))
        end

        DB.transaction do
          DB[:chores].where(id: chore.id).update(updates)
          Broadcaster.object_changed("chore", chore.id)
        end

        updated_chore = Chore.find(chore.id)
        reschedule_reminders(updated_chore) if time_changed

        pool = PoolSerializer.new(membership: membership)
        pool.add(:chore, [updated_chore])

        Success({ objects: pool.to_a })
      end

      # A changed time invalidates every reminder already queued for this
      # chore's assignments. Cancel those still-pending jobs and queue fresh
      # ones — cancelling (rather than relying on the stale-job no-op) is what
      # stops a duplicate when the time is edited back to an earlier value, as
      # that old job's stamp would otherwise match again. Clearing the time
      # cancels and queues nothing. Isolated like other notification work so a
      # scheduling failure can't roll back the saved edit.
      def reschedule_reminders(chore)
        Notifications::Safely.deliver(context: "ChoreRosters::UpdateChore#reminders") do
          ChoreAssignment.for_chore(chore.id).each do |assignment|
            ScheduleReminder.cancel(assignment: assignment)
            ScheduleReminder.call(assignment: assignment, chore: chore)
          end
        end
      end
    end
  end
end
