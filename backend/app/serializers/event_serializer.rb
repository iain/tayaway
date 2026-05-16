# frozen_string_literal: true

# Serializes Event model instances into pool object hashes.
#
# Owns both the field mapping AND the related-object lookups (date_poll, rsvps)
# AND the policy-context prefetch (has_expenses). This is the single source of
# truth for event serialization — called by PoolSerializer at sync time and by
# Websocket::ConnectionManager at broadcast time (via PermissionAttacher).
class EventSerializer
  class << self
    def serialize_batch(events, pool:)
      return [] if events.empty?

      event_ids = events.map { |e| e.id.to_s }
      polls_by_event = DatePoll.for_event_ids(event_ids)
      rsvp_ids_by_event = Rsvp.ids_for_event_ids(event_ids)

      events.map do |event|
        date_poll = polls_by_event[event.id.to_s]
        {
          id: event.id.to_s,
          objectType: "event",
          name: event.name,
          description: event.description,
          startDate: event.start_date&.iso8601,
          endDate: event.end_date&.iso8601,
          locationName: event.location_name,
          latitude: event.location_coordinates&.[](1),
          longitude: event.location_coordinates&.[](0),
          workspaceId: event.workspace_id.to_s,
          userId: event.user_id.to_s,
          datePollId: date_poll&.id&.to_s,
          rsvpIds: rsvp_ids_by_event[event.id.to_s] || [],
          createdAt: event.created_at.iso8601(3),
          updatedAt: event.updated_at.iso8601(3)
        }
      end
    end

    def policy_context_batch(events)
      return {} if events.empty?

      event_ids = events.map { |e| e.id.to_s }
      with_expenses = DB[:expenses].where(event_id: event_ids).distinct.select_map(:event_id).to_set
      with_settlements = DB[:settlements].where(event_id: event_ids).distinct.select_map(:event_id).to_set
      financial = with_expenses | with_settlements

      events.each_with_object({}) do |event, h|
        h[event.id.to_s] = { has_expenses: financial.include?(event.id.to_s) }
      end
    end
  end
end
