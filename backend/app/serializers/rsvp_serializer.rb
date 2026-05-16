# frozen_string_literal: true

class RsvpSerializer
  extend PoolObjectSerializer

  class << self
    def broadcast_audiences_for(rsvp)
      ws_id = DB[:events].where(id: rsvp.event_id).get(:workspace_id)
      [WS_AUD.call(ws_id)]
    end

    def serialize_batch(rsvps, pool:)
      rsvps.map do |rsvp|
        {
          id: rsvp.id.to_s,
          objectType: "rsvp",
          eventId: rsvp.event_id.to_s,
          userId: rsvp.user_id.to_s,
          createdByUserId: rsvp.created_by_user_id&.to_s,
          attending: rsvp.attending,
          startDate: rsvp.start_date&.iso8601,
          endDate: rsvp.end_date&.iso8601,
          createdAt: rsvp.created_at.iso8601(3),
          updatedAt: rsvp.updated_at.iso8601(3)
        }
      end
    end
  end
end
