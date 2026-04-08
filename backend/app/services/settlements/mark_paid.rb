# frozen_string_literal: true

module Settlements
  # Service to toggle paid status on a settlement transfer.
  # Only the transfer recipient (to_user) can mark/unmark a transfer as paid.
  module MarkPaid
    class << self
      include Dry::Monads[:result]

      def call(transfer_id:, paid:, membership:, workspace_id:)
        SettlementTransfer.find_result(transfer_id)
                          .bind { |transfer| SettlementTransferPolicy.enforce(:mark_paid, transfer, membership: membership) }
                          .bind { |transfer| update_paid(transfer, paid, workspace_id) }
      end

      private

      def update_paid(transfer, paid, workspace_id)
        paid_at = paid ? Time.now : nil

        DB[:settlement_transfers].where(id: transfer.id).update(paid_at: paid_at)
        Broadcaster.object_changed("settlement_transfer", transfer.id, workspace_id: workspace_id)

        updated = SettlementTransfer.find(transfer.id)
        pool = PoolSerializer.new(workspace_id: workspace_id)
        pool.add_settlement_transfer(updated)

        Success({ objects: pool.to_a })
      end
    end
  end
end
