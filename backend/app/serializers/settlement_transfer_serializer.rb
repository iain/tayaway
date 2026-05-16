# frozen_string_literal: true

class SettlementTransferSerializer
  extend PoolObjectSerializer

  class << self
    def topics_for(transfer)
      ws_id = DB[:settlements]
              .join(:events, id: :event_id)
              .where(Sequel[:settlements][:id] => transfer.settlement_id)
              .get(Sequel[:events][:workspace_id])
      ["workspace:#{ws_id}"]
    end

    def serialize_batch(transfers, pool:)
      transfers.map do |transfer|
        {
          id: transfer.id.to_s,
          objectType: "settlementTransfer",
          settlementId: transfer.settlement_id.to_s,
          fromUserId: transfer.from_user_id&.to_s,
          toUserId: transfer.to_user_id&.to_s,
          amount: transfer.amount,
          paidAt: transfer.paid_at&.iso8601(3),
          paidByUserId: transfer.paid_by_user_id&.to_s,
          supersededAt: transfer.superseded_at&.iso8601(3),
          createdAt: transfer.created_at.iso8601(3),
          updatedAt: transfer.updated_at.iso8601(3)
        }
      end
    end

    def policy_context_batch(transfers)
      return {} if transfers.empty?

      settlement_ids = transfers.map { |t| t.settlement_id.to_s }.uniq
      settlement_ids_with_successor = DB[:settlements]
                                      .where(previous_settlement_id: settlement_ids)
                                      .select_map(:previous_settlement_id)
                                      .map(&:to_s)
                                      .to_set

      transfers.each_with_object({}) do |transfer, h|
        h[transfer.id.to_s] = {
          has_successor: settlement_ids_with_successor.include?(transfer.settlement_id.to_s)
        }
      end
    end
  end
end
