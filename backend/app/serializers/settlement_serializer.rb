# frozen_string_literal: true

class SettlementSerializer
  extend PoolObjectSerializer

  class << self
    def broadcast_audiences_for(settlement)
      ws_id = DB[:events].where(id: settlement.event_id).get(:workspace_id)
      [WS_AUD.call(ws_id)]
    end

    def serialize_batch(settlements, pool:)
      return [] if settlements.empty?

      settlement_ids = settlements.map { |s| s.id.to_s }
      transfer_ids_by_settlement = SettlementTransfer.ids_for_settlement_ids(settlement_ids)

      settlements.map do |settlement|
        {
          id: settlement.id.to_s,
          objectType: "settlement",
          eventId: settlement.event_id.to_s,
          userId: settlement.user_id&.to_s,
          previousSettlementId: settlement.previous_settlement_id&.to_s,
          transferIds: transfer_ids_by_settlement[settlement.id.to_s] || [],
          createdAt: settlement.created_at.iso8601(3),
          updatedAt: settlement.updated_at.iso8601(3)
        }
      end
    end

    def policy_context_batch(settlements)
      return {} if settlements.empty?

      event_ids = settlements.map { |s| s.event_id.to_s }.uniq
      events_by_id = Event.for_ids(event_ids).each_with_object({}) { |e, h| h[e.id.to_s] = e }

      ids = settlements.map { |s| s.id.to_s }
      ids_with_successor = DB[:settlements]
                           .where(previous_settlement_id: ids)
                           .select_map(:previous_settlement_id)
                           .map(&:to_s)
                           .to_set

      settlements.each_with_object({}) do |settlement, h|
        h[settlement.id.to_s] = {
          event: events_by_id[settlement.event_id.to_s],
          has_successor: ids_with_successor.include?(settlement.id.to_s)
        }
      end
    end
  end
end
