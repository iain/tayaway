# frozen_string_literal: true

class SettlementTransferSerializer
  class << self
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
          createdAt: transfer.created_at.iso8601(3),
          updatedAt: transfer.updated_at.iso8601(3)
        }
      end
    end

    def policy_context(_transfer) = {}
    def policy_context_batch(_transfers) = {}
  end
end
