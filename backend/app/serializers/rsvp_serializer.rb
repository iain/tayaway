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
          createdByUserId: rsvp.created_by_user_id&.to_s,
          attending: rsvp.attending,
          attendance: rsvp.attendance&.map { |day| serialize_day(day) },
          startDate: rsvp.start_date&.iso8601,
          endDate: rsvp.end_date&.iso8601,
          createdAt: rsvp.created_at.iso8601(3),
          updatedAt: rsvp.updated_at.iso8601(3)
        }
      end
    end

    private

    # A guest-free day serializes as a bare ISO string — identical to the
    # original come-and-go wire shape, so clients that predate plus-ones keep
    # reading it. Only guest-bearing days carry the `{date, plusOnes}` object.
    def serialize_day(day)
      if day[:plus_ones].positive?
        { date: day[:date].iso8601, plusOnes: day[:plus_ones] }
      else
        day[:date].iso8601
      end
    end
  end
end
