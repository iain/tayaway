# frozen_string_literal: true

module ChoreRosters
  # Service to update a chore assignment (note, pinned, or the holder). A
  # reassign arrives as an attendance_id, or as a legacy user_id (stale
  # clients and queued offline commands) resolved to the member's attendance
  # row; both columns are kept in step either way.
  module UpdateAssignment
    class << self
      include LengthValidation

      def call(assignment_id:, roster_id:, workspace_id:, membership:, note: nil, user_id: nil, attendance_id: nil, pinned: nil)
        Auditable.around(
          service: "ChoreRosters::UpdateAssignment",
          actor: membership,
          subject_type: "chore_assignment",
          subject_id: assignment_id
        ) do
          Success()
            .bind { validate_length(note, max: ValidationLimits::MEDIUM_TEXT, field: "Note") }
            .bind { validate_holder_params(user_id, attendance_id) }
            .bind { ChoreAssignment.find_result(assignment_id) }
            .bind { |assignment| validate_belongs_to_roster(assignment, roster_id) }
            .bind { |assignment| ChoreAssignmentPolicy.enforce(:edit, assignment, membership: membership) }
            .bind { |assignment| resolve_attendance(assignment, roster_id, user_id, attendance_id, membership) }
            .bind { |ctx| update(ctx, workspace_id, note, pinned, membership) }
        end
      end

      def validate_belongs_to_roster(assignment, roster_id)
        chore = Chore.find(assignment.chore_id)
        if chore && chore.chore_roster_id.to_s == roster_id.to_s
          Success(assignment)
        else
          Failure(ServiceError.not_found("Assignment not found"))
        end
      end

      private

      def validate_holder_params(user_id, attendance_id)
        if given?(user_id) && given?(attendance_id)
          Failure(ServiceError.validation("attendance_id and user_id are mutually exclusive"))
        else
          Success()
        end
      end

      def given?(value)
        !(value.nil? || value.to_s.empty?)
      end

      # Resolves the incoming holder change (if any) to an attendance row on
      # the roster's event, so `update` can write both columns together.
      def resolve_attendance(assignment, roster_id, user_id, attendance_id, membership)
        if !given?(user_id) && !given?(attendance_id)
          Success({ assignment: assignment, attendance: nil })
        else
          Success()
            .bind { find_event(roster_id) }
            .bind { |event| find_holder(event, user_id, attendance_id, membership) }
            .fmap { |attendance| { assignment: assignment, attendance: attendance } }
        end
      end

      def find_event(roster_id)
        Success()
          .bind { ChoreRoster.find_result(roster_id) }
          .bind { |roster| Event.find_result(roster.event_id) }
      end

      def find_holder(event, user_id, attendance_id, membership)
        if given?(attendance_id)
          Success()
            .bind { Attendance.find_result(attendance_id) }
            .bind { |attendance| validate_attendance_on_event(attendance, event) }
            .bind { |attendance| validate_member_attendance(attendance) }
        else
          Attendances::EnsureMemberRow.call(event: event, user_id: user_id, created_by_user_id: membership.user_id)
        end
      end

      def validate_attendance_on_event(attendance, event)
        if attendance.event_id.to_s == event.id.to_s
          Success(attendance)
        else
          Failure(ServiceError.not_found("Attendance not found on this event"))
        end
      end

      # Lifted in the follow-up deploy, once stale clients that can't render
      # a guest assignment are behind the protocol gate.
      def validate_member_attendance(attendance)
        if attendance.guest?
          Failure(ServiceError.validation("Guests cannot be assigned chores yet"))
        else
          Success(attendance)
        end
      end

      def update(ctx, workspace_id, note, pinned, membership)
        assignment, attendance = ctx.values_at(:assignment, :attendance)
        updates = {}
        updates[:note] = note unless note.nil?
        if attendance
          updates[:user_id] = attendance.user_id&.to_s
          updates[:attendance_id] = attendance.id.to_s
        end
        updates[:pinned] = pinned unless pinned.nil?

        if updates.empty?
          return Failure(ServiceError.validation("No changes provided"))
        end

        DB.transaction do
          DB[:chore_assignments].where(id: assignment.id).update(updates)
          Broadcaster.object_changed("chore_assignment", assignment.id)
          # If the holder changed, update parent chore too
          Broadcaster.object_changed("chore", assignment.chore_id) if attendance
        end

        pool = PoolSerializer.new(membership: membership)
        updated = ChoreAssignment.find(assignment.id)
        pool.add(:chore_assignment, [updated])
        chore = Chore.find(assignment.chore_id)
        pool.add(:chore, [chore])

        Success({ objects: pool.to_a })
      end
    end
  end
end
