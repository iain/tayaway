# frozen_string_literal: true

class AttendanceSerializer
  class << self
    def serialize_batch(attendances, pool:)
      attendances.map do |attendance|
        {
          id: attendance.id.to_s,
          objectType: "attendance",
          eventId: attendance.event_id.to_s,
          userId: attendance.user_id&.to_s,
          guestId: attendance.guest_id&.to_s,
          hostUserId: attendance.host_user_id&.to_s,
          status: attendance.status,
          days: attendance.days&.map(&:iso8601),
          createdByUserId: attendance.created_by_user_id&.to_s,
          createdAt: attendance.created_at.iso8601(3),
          updatedAt: attendance.updated_at.iso8601(3)
        }
      end
    end

    # Prefetches the decline blockers for member rows (guest rows always
    # allow decline): whether the subject has expenses on the event, and
    # whether they host going guests there. Batched here so AttendancePolicy
    # doesn't N+1 the sync path.
    def policy_context_batch(attendances)
      return {} if attendances.empty?

      member_pairs = attendances.reject(&:guest?).map { |a| [a.event_id.to_s, a.user_id.to_s] }
      with_expenses = expense_pairs(member_pairs)
      hosting = hosting_pairs(member_pairs)

      attendances.each_with_object({}) do |attendance, h|
        if attendance.guest?
          h[attendance.id.to_s] = {}
        else
          pair = [attendance.event_id.to_s, attendance.user_id.to_s]
          h[attendance.id.to_s] = {
            has_expenses: with_expenses.include?(pair),
            has_going_guests: hosting.include?(pair)
          }
        end
      end
    end

    private

    def expense_pairs(pairs)
      return Set.new if pairs.empty?

      DB[:expenses]
        .where([:event_id, :user_id] => pairs)
        .distinct
        .select_map([:event_id, :user_id])
        .map { |event_id, user_id| [event_id.to_s, user_id.to_s] }
        .to_set
    end

    def hosting_pairs(pairs)
      return Set.new if pairs.empty?

      DB[:attendances]
        .where(status: "going")
        .exclude(guest_id: nil)
        .where([:event_id, :host_user_id] => pairs)
        .distinct
        .select_map([:event_id, :host_user_id])
        .map { |event_id, host_user_id| [event_id.to_s, host_user_id.to_s] }
        .to_set
    end
  end
end
