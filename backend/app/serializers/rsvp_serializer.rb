# frozen_string_literal: true

class RsvpSerializer
  class << self
    def serialize_batch(rsvps, pool:)
      rsvps.map do |rsvp|
        {
          id: rsvp.id.to_s,
          objectType: "rsvp",
          eventId: rsvp.event_id.to_s,
          userId: rsvp.user_id.to_s,
          attending: rsvp.attending,
          startDate: rsvp.start_date&.iso8601,
          endDate: rsvp.end_date&.iso8601,
          createdAt: rsvp.created_at.iso8601(3),
          updatedAt: rsvp.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_rsvp) = {}
    def policy_context_batch(_rsvps) = {}
  end
end
