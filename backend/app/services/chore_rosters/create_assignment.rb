# frozen_string_literal: true

module ChoreRosters
  # Service to pin an assignment (always pinned=true). The assignee arrives
  # as an attendance_id, or as a legacy user_id (stale clients and queued
  # offline commands) that is resolved to the member's attendance row —
  # synthesizing a pending one when they haven't answered yet.
  module CreateAssignment
    class << self
      include LengthValidation

      def call(roster_id:, workspace_id:, membership:, chore_id:, date:, user_id: nil, attendance_id: nil, note: nil, id: nil)
        Auditable.around(
          service: "ChoreRosters::CreateAssignment",
          actor: membership,
          subject_type: "chore_assignment",
          subject_id: id
        ) do
          Success()
            .bind { validate(chore_id, user_id, attendance_id, date) }
            .bind { |valid| validate_length(note, max: ValidationLimits::MEDIUM_TEXT, field: "Note").fmap { valid } }
            .bind { |valid| enforce_policy(roster_id, membership, valid) }
            .bind { |valid| validate_chore_belongs(valid, roster_id) }
            .bind { |valid| validate_date_in_range(valid, roster_id) }
            .bind { |valid| resolve_attendance(valid, roster_id, membership) }
            .bind { |valid| create_assignment(valid, workspace_id, note, id, membership) }
        end
      end

      private

      def validate(chore_id, user_id, attendance_id, date)
        if chore_id.nil? || chore_id.empty?
          return Failure(ServiceError.validation("chore_id is required"))
        end

        if given?(attendance_id) && given?(user_id)
          return Failure(ServiceError.validation("attendance_id and user_id are mutually exclusive"))
        end

        if !given?(attendance_id) && !given?(user_id)
          return Failure(ServiceError.validation("attendance_id or user_id is required"))
        end

        if date.nil? || date.empty?
          return Failure(ServiceError.validation("date is required"))
        end

        Success({ chore_id: chore_id, user_id: user_id, attendance_id: attendance_id, date: Date.parse(date) })
      end

      def given?(value)
        !(value.nil? || value.to_s.empty?)
      end

      def enforce_policy(roster_id, membership, valid)
        roster = ChoreRoster.find(roster_id)
        return Failure(ServiceError.not_found("Roster not found")) unless roster

        ChoreRosterPolicy.enforce(:edit, roster, membership: membership)
                         .fmap { valid }
      end

      def validate_chore_belongs(valid, roster_id)
        chore = Chore.find(valid[:chore_id])
        if chore.nil? || chore.chore_roster_id.to_s != roster_id.to_s
          return Failure(ServiceError.not_found("Chore not found in this roster"))
        end

        Success(valid)
      end

      def validate_date_in_range(valid, roster_id)
        roster = ChoreRoster.find(roster_id)
        return Failure(ServiceError.not_found("Roster not found")) unless roster

        event = Event.find(roster.event_id)
        return Failure(ServiceError.not_found("Event not found")) unless event

        if event.start_date && event.end_date
          if valid[:date] < event.start_date || valid[:date] > event.end_date
            return Failure(ServiceError.validation("Date must be within event date range"))
          end
        end

        Success(valid.merge(event: event))
      end

      def resolve_attendance(valid, _roster_id, membership)
        if valid[:attendance_id]
          Success()
            .bind { Attendance.find_result(valid[:attendance_id]) }
            .bind { |attendance| validate_attendance_on_event(attendance, valid[:event]) }
            .fmap { |attendance| valid.merge(attendance: attendance) }
        else
          Attendances::EnsureMemberRow
            .call(event: valid[:event], user_id: valid[:user_id], created_by_user_id: membership.user_id)
            .fmap { |attendance| valid.merge(attendance: attendance) }
        end
      end

      def validate_attendance_on_event(attendance, event)
        if attendance.event_id.to_s == event.id.to_s
          Success(attendance)
        else
          Failure(ServiceError.not_found("Attendance not found on this event"))
        end
      end

      def create_assignment(valid, workspace_id, note, id, membership)
        # Idempotent replay
        if id
          existing = ChoreAssignment.find(id)
          if existing
            pool = PoolSerializer.new(membership: membership)
            pool.add(:chore_assignment, [existing])
            return Success({ objects: pool.to_a })
          end
        end

        assignment_id = id || SecureRandom.uuid
        attendance = valid[:attendance]
        now = Time.now

        DB.transaction do
          DB[:chore_assignments].insert(
            id: assignment_id,
            chore_id: valid[:chore_id],
            user_id: attendance.user_id&.to_s,
            attendance_id: attendance.id.to_s,
            date: valid[:date],
            pinned: true,
            note: note,
            created_at: now,
            updated_at: now
          )
          Broadcaster.object_changed("chore_assignment", assignment_id)
          # Update parent chore so clients see new assignment_ids
          Broadcaster.object_changed("chore", valid[:chore_id])
        end

        pool = PoolSerializer.new(membership: membership)
        assignment = ChoreAssignment.find(assignment_id)
        pool.add(:chore_assignment, [assignment])
        chore = Chore.find(valid[:chore_id])
        pool.add(:chore, [chore])

        # Post-commit side effect: a failure here must not undo the
        # already-saved assignment, so it's isolated like other
        # notification work.
        Notifications::Safely.deliver(context: "ChoreRosters::CreateAssignment#reminder") do
          timezone = ScheduleReminder.timezone_for_roster(chore.chore_roster_id)
          ScheduleReminder.call(assignment: assignment, chore: chore, timezone: timezone)
        end

        Success({ objects: pool.to_a })
      end
    end
  end
end
