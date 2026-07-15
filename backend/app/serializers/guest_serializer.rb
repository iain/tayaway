# frozen_string_literal: true

class GuestSerializer
  class << self
    def serialize_batch(guests, pool:)
      guests.map do |guest|
        {
          id: guest.id.to_s,
          objectType: "guest",
          workspaceId: guest.workspace_id.to_s,
          name: guest.name,
          placeholder: guest.placeholder,
          createdByUserId: guest.created_by_user_id&.to_s,
          createdAt: guest.created_at.iso8601(3),
          updatedAt: guest.updated_at.iso8601(3)
        }
      end
    end

    # Prefetches the delete blocker: whether any attendance row references
    # the guest. Batched so GuestPolicy doesn't N+1 the sync path.
    def policy_context_batch(guests)
      return {} if guests.empty?

      referenced = DB[:attendances]
                   .where(guest_id: guests.map { |g| g.id.to_s })
                   .distinct
                   .select_map(:guest_id)
                   .map(&:to_s)
                   .to_set

      guests.each_with_object({}) do |guest, h|
        h[guest.id.to_s] = { has_attendances: referenced.include?(guest.id.to_s) }
      end
    end
  end
end
